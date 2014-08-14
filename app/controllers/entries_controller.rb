class EntriesController < ApplicationController

  skip_before_action :verify_authenticity_token, only: [:push_view]
  skip_before_action :authorize, only: [:push_view]

  def index
    @user = current_user
    update_selected_feed!("collection_all")

    feed_ids = @user.subscriptions.pluck(:feed_id)
    @entries = Entry.where(feed_id: feed_ids).page(params[:page]).includes(:feed).sort_preference('DESC')
    @entries = update_with_state(@entries)
    @page_query = @entries

    @append = params[:page].present?

    @type = 'all'
    @data = nil

    @collection_title = 'All'
    @collection_favicon = 'favicon-all'

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def unread
    @user = current_user
    update_selected_feed!('collection_unread')

    unread_entries = @user.unread_entries.select(:entry_id).page(params[:page]).sort_preference(@user.entry_sort)
    @entries = Entry.entries_with_feed(unread_entries, @user.entry_sort)

    @entries = update_with_state(@entries)
    @page_query = unread_entries

    @append = params[:page].present?

    @type = 'unread'
    @data = nil

    @collection_title = 'Unread'
    @collection_favicon = 'favicon-unread'

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def starred
    @user = current_user
    update_selected_feed!("collection_starred")

    starred_entries = @user.starred_entries.select(:entry_id).page(params[:page]).order("published DESC")
    @entries = Entry.entries_with_feed(starred_entries, "published DESC")

    @entries = update_with_state(@entries)
    @page_query = starred_entries

    @append = params[:page].present?

    @type = 'starred'
    @data = nil

    @collection_title = 'Starred'
    @collection_favicon = 'favicon-star'

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def show
    @user = current_user
    @entry = Entry.find params[:id]

    @content_view = false
    if @user.sticky_view_inline == '1'
      subscription = Subscription.find_by(user: @user, feed_id: @entry.feed_id)

      # Subscription will not necessarily be present for starred items
      if subscription.try(:view_inline)
        @content_view = true
        view_inline
        @entry.content = @content
      end
    end

    @decrement = UnreadEntry.where(user_id: @user.id, entry_id: @entry.id).delete_all > 0 ? true : false

    @read = true
    @starred = StarredEntry.where(user_id: @user.id, entry_id: @entry.id).present?
    @feed = @entry.feed
    @tags = @user.tags.where(taggings: {feed_id: @feed}).uniq.collect(&:id)

    @services = sharing_services(@entry)
    respond_to do |format|
      format.js
    end
  end

  def content
    @user = current_user
    @entry = Entry.find params[:id]

    @content_view = params[:content_view] == 'true'

    if @user.sticky_view_inline == '1'
      subscription = Subscription.where(user: @user, feed_id: @entry.feed_id).first
      if subscription.present?
        subscription.update_attributes(view_inline: @content_view)
      end
    end

    view_inline
    @content = ContentFormatter.format!(@content, @entry)
  end

  def mark_all_as_read
    @user = current_user

    if params[:type] == 'feed'
      unread_entries = UnreadEntry.where(user_id: @user.id, feed_id: params[:data])
    elsif params[:type] == 'tag'
      feed_ids = @user.taggings.where(tag_id: params[:data]).pluck(:feed_id)
      unread_entries = UnreadEntry.where(user_id: @user.id, feed_id: feed_ids)
    elsif params[:type] == 'starred'
      starred = @user.starred_entries.pluck(:entry_id)
      unread_entries = UnreadEntry.where(user_id: @user.id, entry_id: starred)
    elsif params[:type] == 'recently_read'
      recently_read = @user.recently_read_entries.pluck(:entry_id)
      unread_entries = UnreadEntry.where(user_id: @user.id, entry_id: recently_read)
    elsif  %w{unread all}.include?(params[:type])
      unread_entries = UnreadEntry.where(user_id: @user.id)
    elsif params[:type] == 'saved_search'
      saved_search = @user.saved_searches.where(id: params[:data]).first
      if saved_search.present?
        params[:query] = saved_search.query
        ids = matched_search_ids(params)
        unread_entries = UnreadEntry.where(user_id: @user.id, entry_id: ids)
      end
    elsif params[:type] == 'search'
      params[:query] = params[:data]
      ids = matched_search_ids(params)
      unread_entries = UnreadEntry.where(user_id: @user.id, entry_id: ids)
    end

    if params[:date].present?
      unread_entries = unread_entries.where('created_at <= :last_unread_date', {last_unread_date: params[:date]})
    end

    unread_entries.delete_all

    if params[:ids].present?
      ids = params[:ids].split(',').map {|i| i.to_i }
      UnreadEntry.where(user_id: @user.id, entry_id: ids).delete_all
    end

    @mark_selected = true
    get_feeds_list

    respond_to do |format|
      format.js
    end
  end

  def preload
    @user = current_user
    ids = params[:ids].split(',').map {|i| i.to_i }
    @entries = Entry.where(id: ids).includes(:feed)
    @entries = update_with_state(@entries)

    # View inline setting
    view_inline_settings = {}
    subscriptions = Subscription.where(user: @user).pluck(:feed_id, :view_inline)
    subscriptions.each { |feed_id, setting| view_inline_settings[feed_id] = setting }

    tags = {}
    taggings = @user.taggings.pluck(:feed_id, :tag_id)
    taggings.each do |feed_id, tag_id|
      if tags[feed_id]
        tags[feed_id] << tag_id
      else
        tags[feed_id] = [tag_id]
      end
    end

    result = {}
    @entries.each do |entry|
      readability = (@user.sticky_view_inline == '1' && view_inline_settings[entry.feed_id] == true)
      locals = {
        entry: entry,
        services: sharing_services(entry),
        read: true, # will always be marked as read when viewing
        starred: entry.starred,
        content_view: false
      }
      result[entry.id] = {
        content: render_to_string(partial: "entries/show", formats: [:html], locals: locals),
        read: entry.read,
        starred: entry.starred,
        tags: tags[entry.feed_id] ? tags[entry.feed_id] : [],
        feed_id: entry.feed_id
      }
    end

    respond_to do |format|
      format.json { render json: result.to_json }
    end
  end

  def mark_as_read
    @user = current_user
    UnreadEntry.where(user: @user, entry_id: params[:id]).delete_all
    render nothing: true
  end

  def mark_direction_as_read
    @user = current_user
    ids = params[:ids].split(',').map {|i| i.to_i }
    if params[:direction] == 'above'
      UnreadEntry.where(user: @user, entry_id: ids).delete_all
    else
      if params[:type] == 'feed'
        UnreadEntry.where(user: @user, feed_id: params[:data]).where.not(entry_id: ids).delete_all
      elsif params[:type] == 'tag'
        feed_ids = @user.taggings.where(tag_id: params[:data]).pluck(:feed_id)
        UnreadEntry.where(user: @user, feed_id: feed_ids).where.not(entry_id: ids).delete_all
      elsif params[:type] == 'starred'
        starred = @user.starred_entries.pluck(:entry_id)
        UnreadEntry.where(user: @user, entry_id: starred).where.not(entry_id: ids).delete_all
      elsif  %w{unread all}.include?(params[:type])
        UnreadEntry.where(user: @user).where.not(entry_id: ids).delete_all
      elsif params[:type] == 'saved_search'
        saved_search = @user.saved_searches.where(id: params[:data]).first
        if saved_search.present?
          params[:query] = saved_search.query
          search_ids = matched_search_ids(params)
          ids = search_ids - ids
          UnreadEntry.where(user_id: @user.id, entry_id: ids).delete_all
        end
      elsif params[:type] == 'search'
        params[:query] = params[:data]
        search_ids = matched_search_ids(params)
        ids = search_ids - ids
        UnreadEntry.where(user_id: @user.id, entry_id: ids).delete_all
      end
    end

    @mark_selected = true
    get_feeds_list

    respond_to do |format|
      format.js
    end
  end

  def search
    @user = current_user
    @escaped_query = params[:query].gsub("\"", "'").html_safe if params[:query]

    @entries = Entry.search(params, @user)
    @entries = update_with_state(@entries)
    @page_query = @entries

    @append = params[:page].present?

    @type = 'all'
    @data = nil

    @search = true

    @collection_title = 'Search'
    @collection_favicon = 'favicon-search'

    @saved_search = SavedSearch.new

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def autocomplete_search
    user = current_user
    escaped_query = params[:query].gsub("\"", "'").html_safe if params[:query]
    params[:size] = 5
    entries = Entry.search(params, user)
    suggestions = entries.map do |entry|
      title = ContentFormatter.summary(entry.title)
      feed = ContentFormatter.summary(entry.feed.title)
      content = "#{feed}: #{title}"
      {
        value: content,
        data: content
      }
    end
    render json: { suggestions: suggestions }.to_json
  end

  def push_view
    user_id = verify_push_token(params[:user])
    @user = User.find(user_id)
    @entry = Entry.find(params[:id])
    UnreadEntry.where(user: @user, entry: @entry).delete_all
    redirect_to @entry.fully_qualified_url, status: :found
  end

  def diff
    @entry = Entry.find(params[:id])
    if @entry.original && @entry.original['content'].present?
      begin
        before = ContentFormatter.format!(@entry.original['content'], @entry)
        after = ContentFormatter.format!(@entry.content, @entry)
        @content = HTMLDiff::Diff.new(before, after).inline_html.html_safe
      rescue HTML::Pipeline::Filter::InvalidDocumentException
        @content = '(comparison error)'
      end
    end
  end

  private

  def sharing_services(entry)
    @user_sharing_services ||= begin
      (@user.sharing_services + @user.supported_sharing_services).sort_by{|sharing_service| sharing_service.label}
    end

    services = []
    @user_sharing_services.each do |sharing_service|
      begin
        services << sharing_service.link_options(entry)
      rescue
      end
    end
    services
  end

  def view_inline
    begin
      if @content_view
        url = @entry.fully_qualified_url
        @content_info = Rails.cache.fetch("content_view:#{Digest::SHA1.hexdigest(url)}:v2") do
          ReadabilityParser.parse(url)
        end
        @content = @content_info.content
      else
        @content = @entry.content
      end
    rescue => e
      @content = '(no content)'
    end

  end

  def matched_search_ids(params)
    params[:load] = false
    query = params[:query]
    entries = Entry.search(params, @user)
    ids = entries.results.map {|entry| entry.id.to_i}
    if entries.total_pages > 1
      2.upto(entries.total_pages) do |page|
        params[:page] = page
        params[:query] = query
        entries = Entry.search(params, @user)
        ids = ids.concat(entries.results.map {|entry| entry.id.to_i})
      end
    end
    ids
  end

end
