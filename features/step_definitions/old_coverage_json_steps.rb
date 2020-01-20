# frozen_string_literal: true

RESULTSET_JSON_PATH = "coverage/.resultset.json"
PATH_PLACE_HOLDER = "$$path"
COMMAND_NAME = "RSpec Different Name to avoid overriding"

Given "the paths in the old .resultset.json are adjusted to the current environment" do
  in_current_directory do
    resultset_json_content = File.read(RESULTSET_JSON_PATH)
    File.write(RESULTSET_JSON_PATH, resultset_json_content.gsub(PATH_PLACE_HOLDER, Dir.pwd))
  end
end

Given "the timestamp in the .resultset.json is current" do
  in_current_directory do
    resultset_json = File.read(RESULTSET_JSON_PATH)
    resultset_hash = JSON.parse(resultset_json)
    resultset_hash[COMMAND_NAME]["timestamp"] = Time.now.to_i
    File.write(RESULTSET_JSON_PATH, JSON.pretty_generate(resultset_hash))
  end
end
