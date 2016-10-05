require 'rails_helper'
describe GAClient do
  it 'map_data' do
    map_data = GAClient::map_data ({password: '413938e7b5256d185b65557d1bb58ec6',user_id: '128853001'})
    json = JSON.parse(map_data)
    expect(json['user_data']).not_to be_empty
    expect(json['hunting_targets']).not_to be_empty
  end
end
