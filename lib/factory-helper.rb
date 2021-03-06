# -*- coding: utf-8 -*-
# frozen_string_literal: true
mydir = File.expand_path(File.dirname(__FILE__))

begin
  require 'psych'
rescue LoadError
end

require 'i18n'
require 'set' # Fixes a bug in i18n 0.6.11

if I18n.respond_to?(:enforce_available_locales=)
  I18n.enforce_available_locales = true
end

I18n.load_path += Dir[File.join(mydir, 'locales', '*.yml')]

module FactoryHelper
  class Config
    class << self
      attr_writer :locale
      attr_reader :random

      def locale
        @locale || I18n.locale
      end

      def seed
        @random.seed
      end

      def seed= new_seed
        new_seed||= Random.new_seed.to_i* Kernel.rand(18446744073709551615).to_i
        @random= Random.new(new_seed)
      end
    end

    self.locale= nil
    self.seed= nil
  end

  class Base
    Numbers = Array(0..9)
    ULetters = Array('A'..'Z')
    Letters = ULetters + Array('a'..'z')

    class << self
      ## make sure numerify results doesn’t start with a zero
      def numerify(number_string)
        number_string.sub(/#/) { (FactoryHelper::Config.random.rand(9)+1).to_s }.gsub(/#/) { FactoryHelper::Config.random.rand(10).to_s }
      end

      def letterify(letter_string)
        letter_string.gsub(/\?/) { ULetters.sample(:random => FactoryHelper::Config.random) }
      end

      def bothify(string)
        letterify(numerify(string))
      end

      # Given a regular expression, attempt to generate a string
      # that would match it.  This is a rather simple implementation,
      # so don't be shocked if it blows up on you in a spectacular fashion.
      #
      # It does not handle ., *, unbounded ranges such as {1,},
      # extensions such as (?=), character classes, some abbreviations
      # for character classes, and nested parentheses.
      #
      # I told you it was simple. :) It's also probably dog-slow,
      # so you shouldn't use it.
      #
      # It will take a regex like this:
      #
      # /^[A-PR-UWYZ0-9][A-HK-Y0-9][AEHMNPRTVXY0-9]?[ABEHMNPRVWXY0-9]? {1,2}[0-9][ABD-HJLN-UW-Z]{2}$/
      #
      # and generate a string like this:
      #
      # "U3V  3TP"
      #
      def regexify(re)
        re = re.source if re.respond_to?(:source) # Handle either a Regexp or a String that looks like a Regexp
        re.
          gsub(/^\/?\^?/, '').gsub(/\$?\/?$/, '').                                                                      # Ditch the anchors
          gsub(/\{(\d+)\}/, '{\1,\1}').gsub(/\?/, '{0,1}').                                                             # All {2} become {2,2} and ? become {0,1}
          gsub(/(\[[^\]]+\])\{(\d+),(\d+)\}/) {|match| $1 * Array(Range.new($2.to_i, $3.to_i)).sample(:random => FactoryHelper::Config.random) }.                # [12]{1,2} becomes [12] or [12][12]
          gsub(/(\([^\)]+\))\{(\d+),(\d+)\}/) {|match| $1 * Array(Range.new($2.to_i, $3.to_i)).sample(:random => FactoryHelper::Config.random) }.                # (12|34){1,2} becomes (12|34) or (12|34)(12|34)
          gsub(/(\\?.)\{(\d+),(\d+)\}/) {|match| $1 * Array(Range.new($2.to_i, $3.to_i)).sample(:random => FactoryHelper::Config.random) }.                      # A{1,2} becomes A or AA or \d{3} becomes \d\d\d
          gsub(/\((.*?)\)/) {|match| match.gsub(/[\(\)]/, '').split('|').sample(:random => FactoryHelper::Config.random) }.                                      # (this|that) becomes 'this' or 'that'
          gsub(/\[([^\]]+)\]/) {|match| match.gsub(/(\w\-\w)/) {|range| Array(Range.new(*range.split('-'))).sample(:random => FactoryHelper::Config.random) } }. # All A-Z inside of [] become C (or X, or whatever)
          gsub(/\[([^\]]+)\]/) {|match| $1.split('').sample(:random => FactoryHelper::Config.random) }.                                                          # All [ABC] become B (or A or C)
          gsub('\d') {|match| Numbers.sample(:random => FactoryHelper::Config.random) }.
          gsub('\w') {|match| Letters.sample(:random => FactoryHelper::Config.random) }
      end

      # Helper for the common approach of grabbing a translation
      # with an array of values and selecting one of them.
      def fetch(key)
        fetched = translate("factory_helper.#{key}")
        fetched = fetched.sample(:random => FactoryHelper::Config.random) if fetched.respond_to?(:sample)
        if fetched.match(/^\//) and fetched.match(/\/$/) # A regex
          regexify(fetched)
        else
          fetched
        end
      end

      # Load formatted strings from the locale, "parsing" them
      # into method calls that can be used to generate a
      # formatted translation: e.g., "#{first_name} #{last_name}".
      def parse(key)
        fetch(key).scan(/(\(?)#\{([A-Za-z]+\.)?([^\}]+)\}([^#]+)?/).map do |prefix, kls, meth, etc|
          # If the token had a class Prefix (e.g., Name.first_name)
          # grab the constant, otherwise use self
          cls = kls ? FactoryHelper.const_get(kls.chop) : self

          # If an optional leading parentheses is not present, prefix.should == "", otherwise prefix.should == "("
          # In either case the information will be retained for reconstruction of the string.
          text = prefix

          # If the class has the method, call it, otherwise
          # fetch the translation (i.e., factory_helper.name.first_name)
          text += cls.respond_to?(meth) ? cls.send(meth) : fetch("#{(kls || self).to_s.split('::').last.downcase}.#{meth.downcase}")

          # And tack on spaces, commas, etc. left over in the string
          text += etc.to_s
        end.join
      end

      # Call I18n.translate with our configured locale if no
      # locale is specified
      def translate(*args)
        opts = args.last.is_a?(Hash) ? args.pop : {}
        opts[:locale] ||= FactoryHelper::Config.locale
        opts[:raise] = true
        I18n.translate(*(args.push(opts)))
      rescue I18n::MissingTranslationData
        # Super-simple fallback -- fallback to en if the
        # translation was missing.  If the translation isn't
        # in en either, then it will raise again.
        I18n.translate(*(args.push(opts.merge(:locale => :en))))
      end

      def flexible(key)
        @flexible_key = key
      end

      # You can add whatever you want to the locale file, and it will get caught here.
      # E.g., in your locale file, create a
      #   name:
      #     girls_name: ["Alice", "Cheryl", "Tatiana"]
      # Then you can call FactoryHelper::Name.girls_name and it will act like #first_name
      def method_missing(m, *args, &block)
        super unless @flexible_key

        # Use the alternate form of translate to get a nil rather than a "missing translation" string
        if translation = translate(:factory_helper)[@flexible_key][m]
          translation.respond_to?(:sample) ? translation.sample(:random => FactoryHelper::Config.random) : translation
        else
          super
        end
      end

      # Generates a random value between the interval
      def rand_in_range(from, to)
        from, to = to, from if to < from
        FactoryHelper::Config.random.rand(from..to)
      end
    end
  end
end

Faker= FactoryHelper

require_relative 'factory-helper/address'
require_relative 'factory-helper/code'
require_relative 'factory-helper/company'
require_relative 'factory-helper/finance'
require_relative 'factory-helper/internet'
require_relative 'factory-helper/lorem'
require_relative 'factory-helper/name'
require_relative 'factory-helper/team'
require_relative 'factory-helper/phone_number'
require_relative 'factory-helper/business'
require_relative 'factory-helper/commerce'
require_relative 'factory-helper/version'
require_relative 'factory-helper/number'
require_relative 'factory-helper/bitcoin'
require_relative 'factory-helper/avatar'
require_relative 'factory-helper/date'
require_relative 'factory-helper/time'
require_relative 'factory-helper/timestamps'
require_relative 'factory-helper/number'
require_relative 'factory-helper/hacker'
require_relative 'factory-helper/app'
require_relative 'factory-helper/slack_emoji'
require_relative 'factory-helper/string'
require_relative 'factory-helper/my_sql'
