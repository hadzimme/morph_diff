# -*- coding: utf-8 -*-

require "iconv"
require "yaml"

class String
  def is_binary_data?
    false
  end
end

class MorphDiff
  def initialize
    @multi_tagger = MultiTagger.new
    @tokens = Array.new
  end

  def compare(string)
    @tokens = @multi_tagger.parse(string)
  end

  def dump
    output_text = "RESULT >> ========================================\n\n"
    @tokens.each do |token|
      output_text += token.dump_data
      output_text += "=== chunked ======================================\n\n"
    end
    return output_text
  end
end

class MorphDiff::MultiTagger
  def initialize
    main_configuration = YAML.load_file("config/main.yml")
    tagger_configuration = main_configuration[:tagger_configuration]
    @taggers = tagger_configuration.map{|name, configuration| Tagger.new(name, configuration)}
    Token.preset(main_configuration[:grammar_pairs])
  end

  def parse(string)
    character_matrix =
      @taggers.map do |tagger|
        result = tagger.parse(string)
        morphemes = result.scan(/#{tagger.pattern}/)
        characters = morphemes.map do |morpheme|
          sub_characters = morpheme[0].split(//).map do |character|
            Character.new(tagger.name, tagger.grammar, *morpheme)
          end
          sub_characters.last.mark_as_chunked
          sub_characters
        end
        characters.flatten
      end
    return Token.tokenize(character_matrix.transpose)
  end
end

class MorphDiff::MultiTagger::Tagger
  def initialize(name, configuration)
    @name = name
    @grammar = configuration[:grammar]
    @pattern = configuration[:pattern]
    option = configuration[:option] || ""
    @tagger =
      case configuration[:tagger]
      when :mecab
        MeCab.new(option)
      when :juman
        JUMAN.new(option)
      else
        raise NotSupportedTaggerError.new("error: not supported tagger")
      end
  end
  attr_reader :name, :grammar, :pattern

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
    @tagger.parse(string).force_encoding("utf-8")
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

class MorphDiff::MultiTagger::Tagger::NotSupportedTaggerError < StandardError
end

class MorphDiff::MultiTagger::Character
  def initialize(tagger_name, grammar, surface, feature01, feature02)
    @tagger_name = tagger_name
    @grammar = grammar
    @surface = surface
    @feature =
      if feature02 == "*"
        feature01
      else
        "#{feature01}_#{feature02}"
      end
    @chunked = false
  end
  attr_reader :tagger_name, :grammar, :surface, :feature

  def mark_as_chunked
    @chunked = true
  end

  def chunked?
    @chunked
  end
end

class MorphDiff::MultiTagger::Token
  def self.preset(grammar_combinations)
    @@grammar_pairs = Array.new
    @@tagger_rule_set = Hash.new
    grammar_combinations.each do |grammar|
      @@grammar_pairs.push(grammar[:combination])
      rule = YAML.load_file(grammar[:config])
      @@tagger_rule_set[grammar[:combination].join("_").intern] = rule
    end
  end

  def self.tokenize(character_matrix)
    tokens = Array.new.push(self.new)
    character_matrix.each do |row|
      row.select{|character| character.chunked?}.each do |character|
        tokens.last.input(character)
      end
      if row.map{|character| character.chunked?}.inject{|result, item| result && item}
        tokens.last.check_pos
        tokens.push(self.new)
      end
    end
    tokens.pop
    return tokens
  end

  def initialize
    @tagger_morpheme_set = Hash.new
    @tagger_sets = Array.new
  end

  def input(character)
    morpheme = Morpheme.new(character.surface, character.feature, character.grammar)
    if @tagger_morpheme_set.keys.include?(character.tagger_name)
      @tagger_morpheme_set[character.tagger_name].push(morpheme)
    else
      @tagger_morpheme_set[character.tagger_name] = Array.new.push(morpheme)
    end
  end

  def check_pos
    @tagger_morpheme_set.keys.combination(2).each do |tagger_pair|
      grammar_pair = tagger_pair.map{|tagger| @tagger_morpheme_set[tagger].last.grammar}
      feature_pair = tagger_pair.map{|tagger| @tagger_morpheme_set[tagger].map{|morpheme| morpheme.feature}.join("/")}
      if grammar_pair.uniq.size == 1
        if feature_pair.uniq.size == 1
          set_same_tagger(tagger_pair)
        else
          set_different_tagger(tagger_pair)
        end
      else
        if @@grammar_pairs.include?(grammar_pair.reverse)
          grammar_pair.reverse!
        elsif ! @@grammar_pairs.include?(grammar_pair)
          raise NotSupportedGrammarPairError.new("error: not supported grammar pair.")
        end
        pos_rule = @@tagger_rule_set[grammar_pair.join("_").intern]
        if pos_rule.keys.include?(feature_pair[0]) && pos_rule[feature_pair[0]].include?(feature_pair[1])
          set_same_tagger(tagger_pair)
        else
          set_different_tagger(tagger_pair)
        end
      end
    end
  end

  def dump_data
    output_text =
      if acceptable?
        "[acceptable]\n\n"
      else
        "[differences have been found]\n\n"
      end
    @tagger_sets.each do |tagger_set|
      output_text += ">> #{tagger_set.join(", ")}\n"
      tagger_set.each do |tagger|
        morphemes = @tagger_morpheme_set[tagger]
        morphemes.each do |morpheme|
          output_text += "#{morpheme.surface}\t#{morpheme.feature}\n"
        end
      end
      output_text += "\n"
    end
    return output_text
  end

  private
  def set_same_tagger(tagger_pair)
    pos0 = @tagger_sets.index{|set| set.include?(tagger_pair[0])}
    pos1 = @tagger_sets.index{|set| set.include?(tagger_pair[1])}
    if pos0 && pos1 && pos0 != pos1
      @tagger_sets[pos0] += @tagger_sets[pos1]
      @tagger_sets.delete_at(pos1)
    elsif pos0 && ! pos1
      @tagger_sets[pos0].push(tagger_pair[1])
    elsif ! pos0 && pos1
      @tagger_sets[pos1].push(tagger_pair[0])
    elsif ! pos0 && ! pos1
      @tagger_sets.push(tagger_pair)
    end
  end

  def set_different_tagger(tagger_pair)
    if ! @tagger_sets.index{|set| set.include?(tagger_pair[0])}
      @tagger_sets.push([tagger_pair[0]])
    end
    if ! @tagger_sets.index{|set| set.include?(tagger_pair[1])}
      @tagger_sets.push([tagger_pair[1]])
    end
  end

  def acceptable?
    @tagger_sets.size == 1
  end
end

class MorphDiff::MultiTagger::Token::Morpheme
  def initialize(surface, feature, grammar)
    @surface = surface
    @feature = feature
    @grammar = grammar
  end
  attr_reader :surface, :feature, :grammar
end

class MorphDiff::MultiTagger::Token::NotSupportedGrammarPairError < StandardError
end
