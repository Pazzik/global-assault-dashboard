class GAClient
  class << self
    # def req_body 
    #   {
    #     # 'password'=>'413938e7b5256d185b65557d1bb58ec6',
    #     # 'user_id'=>'128853001', 
    #     # 'unity'=>'Unity4_6_6',
    #     # 'api_stat_name'=>'setRivalViewed',
    #     # 'api_stat_time'=>'299',
    #     # 'client_version'=>'27',
    #     # 'platform'=>'Web',
    #     # 'name_test'=>'1',
    #     # 'kong_id'=>'123456',
    #     # 'kong_token'=>'kong_token',
    #     # 'kong_name'=>'kong_name',
    #     # 'no_sync'=>'no_sync',
    #     # 'data_usage'=>'179418'                  
    #   }
    # end

    def headers
      {
        "Host" => "havoc.synapse-games.com",
        "User-Agent" => "Mozilla/5.0 (Windows NT 6.1; rv:41.0) Gecko/20100101 Firefox/41.0",
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language" => "ru-RU,ru;q=0.8,en-US;q=0.5,en;q=0.3" ,
        "Connection" => "keep-alive"
      }
    end

    def raid_title
      {
        '101' => 'Guardian Gate',
        '102' => 'Drone Matrix',
        '103' => 'Reactor Epsilon',
        '104' => 'ATMOS',

        '151' => 'Watchtower Foundry',
        '152' => 'Suppression Vats',
        '153' => 'AI Core',

        '201' => 'Nano Generator',
        '202' => 'Cloak and Dagger',
        '203' => 'Hydra',
        '204' => 'Doctor Magnus',

        '251' => 'Ammunition Vault',
        '252' => 'Turret Construction',
        '253' => 'Testing Chamber',
        '254' => 'Defense Pylon'
      }
    end

    def ranking_data(ranking_index)
      url = 'https://havoc.synapse-games.com/api.php?message=getRankings'
      req_body.merge!('ranking_index'=>ranking_index)
      req_body.merge!('ranking_id'=>'raid')
      result = HTTParty.post(url,:body => JSON.parse(req_body.to_json),:header => headers)
      return JSON.parse(result)
    end

    def map_data(password:, user_id: )
      url = 'https://havoc.synapse-games.com/api.php?message=updateMapData'  
      # body = JSON.parse( {user_id: user_id, password: password }.to_json )
      body = JSON.parse({user_id: user_id, password: password}.to_json)
      result = HTTParty.post(url,:body => body,:header => headers)
      return result
    end

    def raid_status
      f = File.open './tmp/data/map_data.json','r'
      data = JSON.parse(f.read)
      f.close     

      raid_status = data['raid_status']
      raid_status.each do |item|          
        item[1].merge!('title' => raid_title[item[0]])
        item[1].merge!('url' => "/raids/#{item[0]}")    
        time =  Time.at(item[1]['respawn_time'].to_i)
        time = time + Time.zone_offset('+00:00')

        killed = item[1]['health'].to_i <= 0
        if ['101','102','103','104','201','202','203','204'].include? item[0]
          status =  'Killed' if killed
        else
          status = time.strftime('%H:%M:%S')  if killed
        end
        
        item[1].merge!('status' => status)
      end

      return raid_status
    end

    def every_n_seconds(n)
      thread = Thread.new do
        while true
          before = Time.now
          yield
          interval = n-(Time.now-before)
          sleep(interval) if interval > 0
        end
      end
      return thread
    end

    def run_jobs
      every_n_seconds(15) do 
        data = map_data
        f= File.open './tmp/data/map_data.json','w'
        f.puts data
        f.close
      end

      every_n_seconds(60) do
       fill_ranking_data
      end
    end 

    def fill_ranking_data
      raid_title.each do |k,v|
        json = ranking_data(k)
        rows = []
        data = json['rankings']['data']
        data.each_with_index do |row,index|
          if (index != 0)
            rows << row
          end         
        end
        Raid.create 'raid_id' => k.to_i,'title' => v,'ranking_data' => rows.to_json             
      end
    end

    def run_battle(user_id)
      # binding.pry
      # start battle
      url = 'https://havoc.synapse-games.com/api.php?message=startHuntingBattle'
      req_body.merge!('target_user_id'=>user_id)
      result = HTTParty.post(url,:body => JSON.parse(req_body.to_json),:header => headers)
      json = JSON.parse(result)
      #play card
      draws = json['battle_data']['turn']['2']['draws']
      # puts draws
      url = 'https://havoc.synapse-games.com/api.php?message=playCard'
      (1..8).each do |i|
        turn = (i*2).to_s
        # puts "turn #{turn}"
        new_draws = json['battle_data']['turn'][turn]['draws']
        # puts "new_draws #{new_draws}"
        new_draw = new_draws.nil? ? nil : new_draws[0]
        # puts "new_draw #{new_draw}"
        draws << new_draw if new_draw.present? and turn != "2"
        # puts "draws #{draws}"
        draw_card = draws[0] if draws[0].present?
        # puts "draw_card #{draw_card}"
        draws.delete_at(0)
        # puts "draws #{draws}"
        req_body.merge!({          
          'card_uid' => draw_card,
          'field_order' => i
          })
        result = HTTParty.post(url,:body => JSON.parse(req_body.to_json),:header => headers)
        json = JSON.parse(result)
        break if json['battle_data']['winner'].present?
      end

      return {
        'winner' => json['battle_data']['winner'],
        'rewards' => json['battle_data']['rewards'],
        'damageTaken' => json['battle_data']['damageTaken']
      }

    rescue
      puts json
    end

  def run_all_battles
    json_data = JSON.parse(map_data)
    return if json_data['hunting_targets'].blank?
    hunting_targets = json_data['hunting_targets'].values 
    targets = hunting_targets#.select{|target| target["is_bounty"] == false}    
    # bounty_targets = hunting_targets.select{|target| target["is_bounty"] == true}     
    return if targets.blank?
    targets.each do |target|
      target_id = target["user_id"]
      result = run_battle(target_id)
      if result.nil? #and result["winner"].nil?
        puts "#{target_id} undefine error"
        next
      end
      win_status = result["winner"].to_i == 1 ? "Win" : "Lose"
      puts "#{target_id} #{win_status}"
    end 
  end

    def user_info
      json_data = JSON.parse(map_data)
      name = json_data["common_fields"]["game_username"]
      money = json_data["common_fields"]["soft_currency_balance"]
      salvage = json_data["common_fields"]["soft_currency_2_balance"]
      league_money = json_data["common_fields"]["soft_currency_3_balance"]
      {
        name: name,
        money: money,
        salvage: salvage,
        league_money: league_money
      }
    end

    def buy_card
      url = "https://havoc.synapse-games.com/api.php?message=buyStoreItem"
      req_body.merge!({
        'item_id'=>1,
        'expected_cost'=>100,
        'cost_type'=>2
        })
      result = HTTParty.post(url,:body => JSON.parse(req_body.to_json),:header => headers)
      json = JSON.parse(result)
    end

    def buy_all_cards
      money = user_info[:money]
      count = (money / 100).to_i
      count.times{ buy_card; puts "buy_card" }
    end
  end
end