# frozen_string_literal: true

require 'json'

require 'net/http'

state_hash = {

  'AL': 'Alabama',

  'AK': 'Alaska',

  'AS': 'American Samoa',

  'AZ': 'Arizona',

  'AR': 'Arkansas',

  'CA': 'California',

  'CO': 'Colorado',

  'CT': 'Connecticut',

  'DE': 'Delaware',

  'DC': 'District Of Columbia',

  'FM': 'Federated States Of Micronesia',

  'FL': 'Florida',

  'GA': 'Georgia',

  'GU': 'Guam',

  'HI': 'Hawaii',

  'ID': 'Idaho',

  'IL': 'Illinois',

  'IN': 'Indiana',

  'IA': 'Iowa',

  'KS': 'Kansas',

  'KY': 'Kentucky',

  'LA': 'Louisiana',

  'ME': 'Maine',

  'MH': 'Marshall Islands',

  'MD': 'Maryland',

  'MA': 'Massachusetts',

  'MI': 'Michigan',

  'MN': 'Minnesota',

  'MS': 'Mississippi',

  'MO': 'Missouri',

  'MT': 'Montana',

  'NE': 'Nebraska',

  'NV': 'Nevada',

  'NH': 'New Hampshire',

  'NJ': 'New Jersey',

  'NM': 'New Mexico',

  'NY': 'New York',

  'NC': 'North Carolina',

  'ND': 'North Dakota',

  'MP': 'Northern Mariana Islands',

  'OH': 'Ohio',

  'OK': 'Oklahoma',

  'OR': 'Oregon',

  'PW': 'Palau',

  'PA': 'Pennsylvania',

  'PR': 'Puerto Rico',

  'RI': 'Rhode Island',

  'SC': 'South Carolina',

  'SD': 'South Dakota',

  'TN': 'Tennessee',

  'TX': 'Texas',

  'UT': 'Utah',

  'VT': 'Vermont',

  'VI': 'Virgin Islands',

  'VA': 'Virginia',

  'WA': 'Washington',

  'WV': 'West Virginia',

  'WI': 'Wisconsin',

  'WY': 'Wyoming'

}

market_cat_hash = {

  'All Sectors': { 'elec_code' => 'ALL', 'gas_code' => 'N/A' },

  'Residential': { 'elec_code' => 'RES', 'gas_code' => '10' },

  'Industrial': { 'elec_code' => 'IND', 'gas_code' => '35' },

  'Commercial': { 'elec_code' => 'COM', 'gas_code' => '20' },

  'Transportation': { 'elec_code' => 'TRA', 'gas_code' => 'N/A' },

  'Other': { 'elec_code' => 'OTH', 'gas_code' => 'N/A' }

}

def api_call(st_code, elec_code, gas_code)
  api_key = 'YOUR_OWN_API_KEY'

  electricity_call = URI("http://api.eia.gov/series/?api_key=#{api_key}&series_id=ELEC.PRICE.#{st_code}-#{elec_code}.A&out=json")

  electricity_hash = JSON.parse(Net::HTTP.get(electricity_call))

  if gas_code == 'N/A'

    gas_hash = nil

  else

    gas_call = URI("http://api.eia.gov/series/?api_key=#{api_key}&series_id=NG.N30#{gas_code}#{st_code}3.A&out=json")

    gas_hash = JSON.parse(Net::HTTP.get(gas_call))

  end

  pairs_hash = {

    'Electricity': electricity_hash,

    'Gas': gas_hash

  }

  pairs_hash
end

# Create utility rates hash to save all the series

utility_rates = {}

state_hash.each do |st_code, name|
  # Organize series by state name
  utility_rates[name] = {}

  market_cat_hash.each do |market, codes|
    # Organize series by market and state name
    utility_rates[name][market] = {}

    # Send the call to the API, returns electrical and gas series
    utilities_pairs = api_call(st_code, codes['elec_code'], codes['gas_code'])

    utilities_pairs.each do |u, call|

      # Filter empty calls
      next if call.nil?

      next unless call.key?('series')

      year_data = call['series'][0]['data']

      year_hash = {}

      year_data.each do |y|
        # Some years return 0 or nil, ignore those

        next if y[1].nil? || y[1].zero?

        year_hash[y[0].to_i] = y[1]
      end

      prop_hash = {

        'Long Description' => call['series'][0]['name'],

        'Units' => call['series'][0]['units'],

        'Years' => year_hash

      }
      # Organize series by utility, market, and state
      utility_rates[name][market][u] = prop_hash
    end
  end
end

output_file_path = "#{Dir.pwd}/utility_rates.json"

File.open(output_file_path, 'wb') do |file|
  file.puts utility_rates.to_json

  puts 'Finished writing values to utility_rates.json'
end
