window.feedbin ?= {}

class _Counts
  constructor: (options) ->
    @setData(options)

  update: (options) ->
    @setData(options)

  setData: (options) ->
    @tagMap = @buildTagMap(options.tag_map)
    @collections =
      unread: @sort(options.unread_entries, options.sort_order)
      starred: @sort(options.starred_entries, 'DESC')
    @counts =
      unread: @organizeCounts(@collections.unread)
      starred: @organizeCounts(@collections.starred)

  removeEntry: (entryId, feedId, collection) ->
    index = @counts[collection].all.indexOf(entryId);
    if index > -1
      @counts[collection].all.splice(index, 1);
      @collections[collection].splice(index, 1);

    @removeFromCollection(collection, 'byFeed', entryId, feedId)

    if (feedId of @tagMap)
      tags = @tagMap[feedId]
      for tagId in tags
        @removeFromCollection(collection, 'byTag', entryId, tagId)

  addEntry: (entryId, feedId, published, collection) ->
    entry = @buildEntry
      feedId: feedId
      entryId: entryId
      published: published
    @collections[collection].push(entry)
    @collections[collection] = @sort(@collections[collection])
    @counts[collection] = @organizeCounts(@collections[collection])

  organizeCounts: (entries) ->
    counts =
      byFeed: {}
      byTag: {}
      all: []

    for entry in entries
      feedId = @feedId(entry)
      entryId = @entryId(entry)

      counts.all.push(entryId)
      counts.byFeed[feedId] = counts.byFeed[feedId] || []
      counts.byFeed[feedId].push(entryId)

      if (feedId of @tagMap)
        tags = @tagMap[feedId]
        for tagId in tags
          counts.byTag[tagId] = counts.byTag[tagId] || []
          counts.byTag[tagId].push(entryId)

    counts

  sort: (entries, sortOrder) ->
    if sortOrder == 'ASC'
      entries.sort (a, b) =>
        @published(a) - @published(b)
    else
      entries.sort (a, b) =>
        @published(b) - @published(a)
    entries

  removeFromCollection: (collection, group, entryId, groupId) ->
    index = @counts[collection][group][groupId].indexOf(entryId);
    if index > -1
      @counts[collection][group][groupId].splice(index, 1);
    index

  buildTagMap: (tagArray) ->
    object = {}
    object[item[0]] = item[1] for item in tagArray
    object

  buildEntry: (params) ->
    [params.feedId, params.entryId, params.published]

  feedId: (entry) ->
    entry[0]

  entryId: (entry) ->
    entry[1]

  published: (entry) ->
    entry[2]

  isRead: (entryId) ->
    !_.contains(@counts.unread.all, entryId)

  isStarred: (entryId) ->
    _.contains(@counts.starred.all, entryId)

  getUnreadIds: (group, groupId) ->
    ids = @counts['unread'][group]

    if groupId
      if groupId of ids
        ids = ids[groupId]
      else
        ids = []

    ids.slice()

  bulkRemoveUnread: (entryIds) ->
    $.each entryIds, (index, entryId) =>
      index = @counts.unread.all.indexOf(entryId);
      if index > -1
        @counts.unread.all.splice(index, 1)
        entry = @collections.unread[index]
        feedId = @feedId(entry)
        @collections.unread.splice(index, 1)

      @removeFromCollection('unread', 'byFeed', entryId, feedId)

      if (feedId of @tagMap)
        tags = @tagMap[feedId]
        for tagId in tags
          @removeFromCollection('unread', 'byTag', entryId, tagId)

class Counts
  instance = null
  @get: (tagMap, sortOrder, unreadEntries, starredEntries) ->
    instance ?= new _Counts(tagMap, sortOrder, unreadEntries, starredEntries)

feedbin.Counts = Counts