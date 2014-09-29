class FeedPresenter < BasePresenter

  presents :feed

  def feed_link(&block)
    @template.link_to @template.feed_entries_path(feed), remote: true, title: feed.title, class: 'feed-link', data: { behavior: 'selectable show_entries open_item feed_link countable', count_group: 'byFeed', count_group_id: feed.id, mark_read: {type: 'feed', data: feed.id, message: "Mark #{feed.title} as read?"}.to_json } do
      yield
    end
  end

  def classes
    @template.selected("feed_#{feed.id}")
  end

end