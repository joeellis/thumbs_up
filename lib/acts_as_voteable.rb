module ThumbsUp
  module ActsAsVoteable #:nodoc:

    def self.included(base)
      base.extend ThumbsUp::Base
      base.extend ClassMethods
    end

    module ClassMethods
      def acts_as_voteable
        has_many ThumbsUp.configuration[:voteable_relationship_name],
                 :as => :voteable,
                 :dependent => :destroy,
                 :class_name => 'Vote'

        include ThumbsUp::ActsAsVoteable::InstanceMethods
        extend  ThumbsUp::ActsAsVoteable::SingletonMethods
      end
    end

    module SingletonMethods

      # Calculate the plusminus for a group of voteables in one database query.
      # This returns an Arel relation, so you can add conditions as you like chained on to
      # this method call.
      # i.e. Posts.tally.where('votes.created_at > ?', 2.days.ago)
      # You can also have the upvotes and downvotes returned separately in the same query:
      # Post.plusminus_tally(:separate_updown => true)
      def plusminus_tally(params = {})
        t = self.joins("LEFT OUTER JOIN #{Vote.table_name} ON #{self.table_name}.id = #{Vote.table_name}.voteable_id AND #{Vote.table_name}.voteable_type = '#{self.name}'")
        t = t.order("plusminus_tally DESC")
        t = t.group(column_names_for_tally)
        t = t.select("#{self.table_name}.*")
        t = t.select("SUM(CASE #{Vote.table_name}.vote WHEN #{quoted_true} THEN 1 WHEN #{quoted_false} THEN -1 ELSE 0 END) AS plusminus_tally")
        if params[:separate_updown]
          t = t.select("SUM(CASE #{Vote.table_name}.vote WHEN #{quoted_true} THEN 1 WHEN #{quoted_false} THEN 0 ELSE 0 END) AS up")
          t = t.select("SUM(CASE #{Vote.table_name}.vote WHEN #{quoted_true} THEN 0 WHEN #{quoted_false} THEN 1 ELSE 0 END) AS down")
        end
        t = t.select("COUNT(#{Vote.table_name}.id) AS vote_count")
      end

      # #rank_tally is depreciated.
      alias_method :rank_tally, :plusminus_tally

      # Calculate the vote counts for all voteables of my type.
      # This method returns all voteables (even without any votes) by default.
      # The vote count for each voteable is available as #vote_count.
      # This returns an Arel relation, so you can add conditions as you like chained on to
      # this method call.
      # i.e. Posts.tally.where('votes.created_at > ?', 2.days.ago)
      def tally(*args)
        options = args.extract_options!

        # Use the explicit SQL statement throughout for Postgresql compatibility.
        vote_count = "COUNT(#{Vote.table_name}.voteable_id)"

        # Column commented out to support showing 0 votes for models.  This line won't work as
        # if there are no votes for a model, then it can't filter by this where clause, so the
        # results come out as null, instead of just counting it as 0.
        # t = self.where("#{Vote.table_name}.voteable_type = '#{self.name}'")

        # We join so that you can order by columns on the voteable model.
        t = self.joins("LEFT OUTER JOIN #{Vote.table_name} ON #{self.table_name}.#{self.primary_key} = #{Vote.table_name}.voteable_id")

        t = t.group("#{Vote.table_name}.voteable_id, #{column_names_for_tally}")
        t = t.limit(options[:limit]) if options[:limit]
        t = t.where("#{Vote.table_name}.created_at >= ?", options[:start_at]) if options[:start_at]
        t = t.where("#{Vote.table_name}.created_at <= ?", options[:end_at]) if options[:end_at]
        t = t.where(options[:conditions]) if options[:conditions]
        t = options[:order] ? t.order(options[:order]) : t.order("#{vote_count} DESC")

        # I haven't been able to confirm this bug yet, but Arel (2.0.7) currently blows up
        # with multiple 'having' clauses. So we hack them all into one for now.
        # If you have a more elegant solution, a pull request on Github would be greatly appreciated.
        t = t.having([
            "#{vote_count} >= 0",
            (options[:at_least] ? "#{vote_count} >= #{sanitize(options[:at_least])}" : nil),
            (options[:at_most] ? "#{vote_count} <= #{sanitize(options[:at_most])}" : nil)
            ].compact.join(' AND '))
        # t = t.having("#{vote_count} > 0")
        # t = t.having(["#{vote_count} >= ?", options[:at_least]]) if options[:at_least]
        # t = t.having(["#{vote_count} <= ?", options[:at_most]]) if options[:at_most]
        t.select("#{self.table_name}.*, COUNT(#{Vote.table_name}.voteable_id) AS vote_count")
      end

      def column_names_for_tally
        column_names.map { |column| "#{self.table_name}.#{column}" }.join(', ')
      end

    end

    module InstanceMethods

      # wraps the dynamic, configured, relationship name
      def _votes_on
        self.send(ThumbsUp.configuration[:voteable_relationship_name])
      end

      def votes_for
        self._votes_on.where(:vote => true).count
      end

      def votes_against
        self._votes_on.where(:vote => false).count
      end

      def percent_for
        (votes_for.to_f * 100 / (self._votes_on.size + 0.0001)).round
      end

      def percent_against
        (votes_against.to_f * 100 / (self._votes_on.size + 0.0001)).round
      end

      # You'll probably want to use this method to display how 'good' a particular voteable
      # is, and/or sort based on it.
      # If you're using this for a lot of voteables, then you'd best use the #plusminus_tally
      # method above.
      def plusminus
        respond_to?(:plusminus_tally) ? plusminus_tally : (votes_for - votes_against)
      end

      # The lower bound of a Wilson Score with a default confidence interval of 95%. Gives a more accurate representation of average rating (plusminus) based on the number of positive ratings and total ratings.
      # http://evanmiller.org/how-not-to-sort-by-average-rating.html
      def ci_plusminus(confidence = 0.95)
        require 'statistics2'
        n = self._votes_on.size
        if n == 0
          return 0
        end
        z = Statistics2.pnormaldist(1 - (1 - confidence) / 2)
        phat = 1.0 * votes_for / n
        (phat + z * z / (2 * n) - z * Math.sqrt((phat * (1 - phat) + z * z / (4 * n)) / n)) / (1 + z * z / n)
      end

      def votes_count
        _votes_on.size
      end

      def voters_who_voted
        _votes_on.map(&:voter).uniq
      end

      def voters_who_voted_for
          _votes_on.where(:vote => true).map(&:voter).uniq
      end

      def voters_who_voted_against
          _votes_on.where(:vote => false).map(&:voter).uniq
      end

      def voted_by?(voter)
        0 < Vote.where(
              :voteable_id => self.id,
              :voteable_type => self.class.base_class.name,
              :voter_id => voter.id
            ).count
      end

    end
  end
end
