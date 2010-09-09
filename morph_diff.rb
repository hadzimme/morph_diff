# -*- coding: utf-8 -*-

require "iconv"
require "yaml"
require "yaml/encoding"

class String
  def is_binary_data?
    false
  end
end

class MorphDiff
  def initialize
    config = YAML.load_file("config/main.yml")
    @grammar_configs = config[:grammar_configs]
    @multi_tagger = MultiTagger.new(config[:tagger_config])
    @tokens = nil
  end

  def compare(string)
    @tokens = @multi_tagger.parse(string)
  end

  def dump
    @tokens.each do |token|
      token.dump
    end
  end

  def save
  end

  def hogehoge
    @characters = Array.new(string.size){|i| Character.new}
    tagger_result = @multi_tagger.parse(string)

    tagger_result.each do |tagger, result|
      regexp = Regexp.new(config[:pattern], nil, "u")
      morphemes = result.scan(regexp)
      results = Array.new

      morphemes.each do |morpheme|
        morpheme.surface.size.times do
          feature =
            if morpheme[2] == "*"
              morpheme[1]
            else
              morpheme[1..2].join("_")
            end
          results.push({
            :tagger => tagger,
            :grammar => @tagger_config[tagger][:grammar],
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

    token = MorphDiff::Token.new(@grammar_configs)

    characters = matrix.transpose.map{|character_set| Character.new(character_set)}

    @characters.each do |character|
      character.results_chunked.each do |result|
        token.input(result)
      end
      if character.all_chunked?
        token.dump
        token.clear
      end
    end

    return nil
  end
end

class MorphDiff::MultiTagger
  def initialize
    tagger_config = Hash.new ###############
    @taggers = tagger_config.map{|tagger_name, config| Tagger.new(tagger_name, config[:grammar], config[:option]}
  end

  def parse(string)
    matrix = @taggers.map do |tagger|
      result = tagger.parse(string)
      regexp = Regexp.new(config[:pattern])
      morphemes = result.scan(regexp)
      characters = morphemes.map do |morpheme|
        morpheme[0].split(//).map{|character| Character.new(*morpheme[1..-1])}
      end
      characters.flatten
    end
    matrix.transpose.map{|character_set| Token.new(character_set)}
  end
end

class MorphDiff::MultiTagger::Tagger
  def initialize(tagger_name, grammar, option = "")
    @tagger =
      case grammar
      when :mecab
        MeCab.new(option)
      when :juman
        JUMAN.new(option)
      else
        raise NotSupportedTaggerError.new("not supported tagger")
      end
  end

  def parse(string)
    @tagger.parse(string)
  end
end

class MorphDiff::MultiTagger::Tagger::MeCab
  def initialize(option)
    require "MeCab"
    @tagger = MeCab::Tagger.new(option)
  end

  def parse(string)
    @tagger.parse(string)
  end
end

class MorphDiff::MultiTagger::Tagger::JUMAN
  def initialize(option)
    @option = option
  end

  def parse(string)
    string = Iconv.conv("euc-jp", "utf-8", string)
    result = %x{echo #{string} | juman #{@option}}
    Iconv.conv("utf-8", "euc-jp", result)
  end
end

class MorphDiff::MultiTagger::Token
  def initialize(character_set)
    @character_set = character_set
    @configs = Array.new
    configs.each do |config|
      @configs.push({
        :combination => config[:combination],
        :pattern => YAML.load_file(config[:config]),
      })
    end
    clear
  end

  def input(result)
    if @result.keys.include?(result[:tagger])
      @result[result[:tagger]].push(result)
    else
      @result[result[:tagger]] = Array.new.push(result)
    end
  end

  def dump
    check_pos
    @dump_results.each do |taggers|
      taggers.each do |tagger|
        puts "[#{tagger.to_s}]"
      end
      @result[taggers.first].each do |result|
        puts "#{result[:surface]}\t#{result[:feature]}"
      end
    end
    puts "=== chunked ======================================"
  end

  def clear
    @result = Hash.new
    @dump_map = Hash.new
    @dump_results = Array.new
  end

  private
  def check_pos
    taggers = @result.keys
    taggers.each_with_index do |tagger, index|
      @dump_map[tagger] = index
    end
    @dump_results = taggers.map{|tagger| Array.new.push(tagger)}
    (taggers.size - 1).times do
      tagger01 = taggers.shift
      taggers.each do |tagger02|
        combination = [tagger01, tagger02].map{|tagger| @result[tagger].first[:grammar]}
        if combination.uniq.size == 1
          feature01 = @result[tagger01].map{|result| result[:feature]}.join("/")
          feature02 = @result[tagger02].map{|result| result[:feature]}.join("/")
          if feature01 == feature02 && @dump_map[tagger01] != @dump_map[tagger02]
            @dump_results[@dump_map[tagger01]].concat(@dump_results[@dump_map[tagger02]])
            @dump_results.delete_at(@dump_map[tagger02])
            @dump_results.each_with_index do |results, index|
              results.each do |result|
                @dump_map[result] = index
              end
            end
          end
        else
          @configs.each do |config|
            if config[:combination] == combination
              feature01 = @result[tagger01].map{|result| result[:feature]}.join("/")
              feature02 = @result[tagger02].map{|result| result[:feature]}.join("/")
              if config[:pattern].keys.include?(feature01) && config[:pattern][feature01].include?(feature02) && @dump_map[tagger01] != @dump_map[tagger02]
                @dump_results[@dump_map[tagger01]].concat(@dump_results[@dump_map[tagger02]])
                @dump_results.delete_at(@dump_map[tagger02])
                @dump_results.each_with_index do |results, index|
                  results.each do |result|
                    @dump_map[result] = index
                  end
                end
              end
            elsif config[:combination] == combination.reverse
              feature01 = @result[tagger02].map{|result| result[:feature]}.join("/")
              feature02 = @result[tagger01].map{|result| result[:feature]}.join("/")
              if config[:pattern].keys.include?(feature01) && config[:pattern][feature01].include?(feature02) && @dump_map[tagger01] != @dump_map[tagger02]
                @dump_results[@dump_map[tagger01]].concat(@dump_results[@dump_map[tagger02]])
                @dump_results.delete_at(@dump_map[tagger02])
                @dump_results.each_with_index do |results, index|
                  results.each do |result|
                    @dump_map[result] = index
                  end
                end
              end
            else
              next
            end
          end
        end
      end
    end
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
      return true
    else
      return false
    end
  end
end
