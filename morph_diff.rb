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
    @characters = Array.new(string.split(//u).size){|i| Character.new}
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
    token = MorphDiff::Token.new
    @characters.each do |character|
      results = character.results_chunked
      token.input(results)
      if character.all_chunked?
        token.dump
        token = MorphDiff::Token.new
      end
    end
    nil
  end
end

class MorphDiff::Character
  def initialize
    @results = Array.new
  end

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

class MorphDiff::Token
  def initialize
    @result = Hash.new
  end

  def input(results)
    results.each do |result|
      if @result.keys.include?(result[:tagger])
        @result[result[:tagger]].push(result)
      else
        @result[result[:tagger]] = Array.new.push(result)
      end
    end
  end

  def dump
    @result.each do |tagger, results|
      puts "[#{tagger.to_s}]"
      results.each do |result|
        puts "#{result[:surface]}\t#{result[:feature]}"
      end
    end
    puts "=== chunked ======================================"
  end
end
