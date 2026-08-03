# Defense-in-depth cap on any endpoint that ends up honoring a client-supplied
# per_page/per param (see CBZ HelpEngine Security Assessment finding #4 —
# unrestricted resource consumption via pagination). Most list endpoints
# already hardcode their own RESULTS_PER_PAGE server-side and ignore this
# param entirely; this just bounds the ones that don't.
Kaminari.configure do |config|
  config.max_per_page = 100
end
