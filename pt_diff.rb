require "iconv"
require "yaml"
require "yaml/encoding"
require "string_is_not_binary"

class PtDiff
  def initialize
    config = YAML.load_file("config/main.yml")
    @tagger_config = config[:tagger_config]
    @grammar_configs = config[:grammar_configs]
    @result = Hash.new
  end

  def compare(string)
    @tagger_config.each_key do |tagger|
      command = "echo #{string} | "
      if @tagger_config[tagger][:encoding] != "utf-8"
        command += "iconv -t #{@tagger_config[tagger][:encoding]} -f utf-8 | "
      end
      command += @tagger_config[tagger][:command]}
      result = `#{command}`
      if @tagger_config[tagger][:encoding] != "utf-8"
        result = Iconv.conv("utf-8", @tagger_config[tagger][:encoding], result)
      end
    end
  end
end
