require "iconv"
require "yaml"
require "yaml/encoding"
require "string_is_not_binary"

class MorphDiff
  def initialize
    config = YAML.load_file("config/main.yml")
    @tagger_config = config[:tagger_config]
    @grammar_configs = config[:grammar_configs]
    @characters = nil
  end

  def compare(string)
    @characters = string.split(//u).map{|character| Character.new(character)}
    @tagger_config.each do |tagger, config|
      if config[:encoding] == "utf-8"
        result = %x{echo #{string} | #{config[:command]}}
      else
        strcnv = Iconv.conv(config[:encoding], "utf-8", string)
        result = %x{echo #{strcnv} | #{config[:command]}}
        result = Iconv.conv("utf-8", config[:encoding], result)
      end
      regexp = Regexp.new(config[:pattern], nil, "u")
      mophemes = result.scan(regexp)
      results = Array.new
      mophemes.each do |morpheme|
        morpheme[0].split(//u).size.times do
          feature =
            if morpheme[2] == "*"
              morpheme[1]
            else
              morpheme[1..2].join("_")
            end
          results.push({
            :tagger => tagger,
            :surface => morpheme[0],
            :feature => feature,
            :chunked => false,
          })
        end
        results.last[:chunked] = true
      end
      results.each_with_index do |result, index|
        @characters[index].input(result)
      end
    end
    cursor = Hash.new
    @characters.each do |character|
      character.results_chunked.each do |result|
        if cursor.keys.include?(result[:tagger])
          cursor[result[:tagger]].push(result)
        else
          cursor[result[:tagger]] = Array.new.push(result)
        end
      end
      if character.all_chunked?
        cursor.each do |tagger, results|
          puts tagger.to_s
          results.each do |result|
            puts "#{result[:surface]}\t#{result[:feature]}"
          end
        end
        puts "chunked ======================================"
        cursor = Hash.new
      end
    end
    nil
  end

  def show
    puts YAML.unescape(YAML.dump(@result))
  end
end

class MorphDiff::Character
  def initialize(character)
    @character = character
    @results = Array.new
  end
  attr_reader :character, :surface, :feature, :chunked

  def input(result)
    @results.push(result)
  end

  def results_chunked
    @results.select{|result| result[:chunked]}
  end

  def all_chunked?
    if @results.map{|result| result[:chunked]}.inject{|result, value| result && value}
      true
    else
      false
    end
  end
end
