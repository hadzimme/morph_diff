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
    @tagger_config.each do |tagger, config|
      command = "echo #{string} | "
      if config[:encoding] != "utf-8"
        command += "iconv -t #{config[:encoding]} -f utf-8 | "
      end
      command += config[:command]
      result = `#{command}`
      if config[:encoding] != "utf-8"
        result = Iconv.conv("utf-8", config[:encoding], result)
      end
      regexp = Regexp.new(config[:pattern], nil, "u")
      mophemes = result.scan(regexp)
      @result[tagger] = mophemes
    end
  end

  def show
    puts YAML.unescape(YAML.dump(@result))
  end
end
