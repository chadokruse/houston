window.Houston ?= {}

Houston._ROOT_ROUTE = Meteor.settings?.public?.houston_root_route or "/admin"
Houston._subscribe = (name) -> Meteor.subscribe Houston._houstonize name

Houston._subscribe 'collections'

setup_collection = (collection_name, document_id) ->
  Houston._page_length = 20
  subscription_name = Houston._houstonize collection_name
  collection = Houston._get_collection(collection_name)
  filter = if document_id
    # Sometimes you can lookup with _id being a string, sometimes not
    # When id can be wrapped in an ObjectID, it should
    # It can't if it isn't 12 bytes (24 characters)
    if typeof(document_id) == 'string' and document_id.length == 24
      document_id = new Meteor.Collection.ObjectID(document_id)
    {_id: document_id}
  else
    {}
  Houston._paginated_subscription =
    Meteor.subscribeWithPagination subscription_name, {}, filter,
      Houston._page_length
  Houston._session('collection_name', collection_name)
  return [collection, Houston._paginated_subscription]

Houston._houstonize_route = (name) ->
  Houston._houstonize(name)[1..]

Houston._go = (route_name, options) ->
  Router.go Houston._houstonize_route(route_name), options

Router.map ->
  houston_route = (route_name, options) =>
    # Append _houston_ to template and route names to avoid clobbering parent route namespace
    options.template = Houston._houstonize(options.template)
    options.layoutTemplate = null
    options.path = "#{Houston._ROOT_ROUTE}#{options.houston_path}"
    options.waitOn = ->
      ready: -> !Meteor.loggingIn() and Houston._subscribe('admin_user').ready()
    options.action = -> if @ready() then @render()
    options.path = "#{Houston._ROOT_ROUTE}#{options.houston_path}"
    @route Houston._houstonize_route(route_name), options

  houston_route 'home',
    houston_path: "/",
    onBeforeAction: ->
      # TODO use wait
      Houston._session 'collections', Houston._collections.collections.find().fetch()
    template: 'db_view'

  houston_route 'login',
    houston_path: "/login"
    template: 'login'

  houston_route 'custom_template',
    houston_path: "/:template"
    template: 'custom_template_view'
    data: -> this.params

  houston_route 'change_password',
    houston_path: "/password",
    template: 'change_password'

  houston_route 'collection',
    houston_path: "/collection/:name"
    data: ->
      [collection, @subscription] = setup_collection(@params.name)
      {collection}
    waitOn: -> @subscription
    template: 'collection_view'

  houston_route 'document',
    houston_path: "/:collection/:_id"
    data: ->
      Houston._session('document_id', @params._id)
      [collection, @subscription] = setup_collection(
        @params.collection, @params._id)
      {collection, name: @params.collection}
    template: 'document_view'

# ########
# filters
# ########
mustBeAdmin = ->
  if @ready() and not Houston._user_is_admin Meteor.userId()
    @stop()
    Houston._go 'login'

# If the host app doesn't have a router, their html may show up
hide_non_admin_stuff = ->
  $('body').hide()
  func = ->
    $('body').show()
    $('body').children().hide()
    $('body>.houston').show()
    $('body').css('visibility','hidden')
    $('body>.houston').css('visibility', 'visible')
  setTimeout func, 0

remove_host_css = ->
  $links = $('link[rel="stylesheet"]')
  for link in $links
    $link = $(link)
    $link.remove()


Router.onBeforeAction mustBeAdmin,
  only: (Houston._houstonize_route(name) for name in ['home', 'collection', 'document', 'change_password'])
Router.onBeforeAction hide_non_admin_stuff,
  only: (Houston._houstonize_route(name) for name in ['home', 'collection', 'document', 'login', 'custom_template'])
Router.onBeforeAction remove_host_css,
  only: (Houston._houstonize_route(name) for name in ['home', 'collection', 'document', 'login'])

onRouteNotFound = Router.onRouteNotFound
Router.onRouteNotFound = (args...) ->
  non_houston_routes = _.filter(Router.routes, (route) -> route.name.indexOf('houston_') != 0)
  if non_houston_routes.length > 0
    onRouteNotFound.apply Router, args
  else
    console.log "Note: Houston is suppressing Iron-Router errors because we don't think you are using it."
