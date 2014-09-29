class EntriesController < ApplicationController

  skip_before_action :verify_authenticity_token, only: [:push_view]
  skip_before_action :authorize, only: [:push_view]

  def index
    @user = current_user
    update_selected_feed!("collection_all")

    feed_ids = @user.subscriptions.pluck(:feed_id)
    @entries = Entry.where(feed_id: feed_ids).page(params[:page]).includes(:feed).sort_preference('DESC')
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
    @entries = entries_by_id(params[:id])
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
    @user.unread_entries.where(entry_id: params[:ids]).delete_all
    render nothing: true
  end

  def preload
    @user = current_user
    ids = params[:ids].split(',').map {|i| i.to_i }
    entries = entries_by_id(ids)
    render json: entries.to_json
  end

  def entries_by_id(entry_ids)
    entries = Entry.where(id: entry_ids).includes(:feed)
    entries.each_with_object({}) do |entry, hash|
      locals = {
        entry: entry,
        services: sharing_services(entry),
        content_view: false
      }
      hash[entry.id] = {
        content: render_to_string(partial: "entries/show", formats: [:html], locals: locals),
        feed_id: entry.feed_id
      }
    end
  end

  def preload_summaries
    @user = current_user
    ids = params[:ids].split(',').map {|i| i.to_i }
    entries = Entry.where(id: ids).includes(:feed)
    entries = entries.each_with_object({}) do |entry, hash|
      hash[entry.id] = render_to_string(partial: "entries/entry", formats: [:html], locals: {entry: entry})
    end
    render json: entries.to_json
  end

  def mark_as_read
    @user = current_user
    UnreadEntry.where(user: @user, entry_id: params[:id]).delete_all
    render nothing: true
  end

  def search
    @user = current_user
    @escaped_query = params[:query].gsub("\"", "'").html_safe if params[:query]

    @entries = Entry.search(params, @user)
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
