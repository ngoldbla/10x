# gc_setup.rb — one-time Game Center configuration for Nine via the App
# Store Connect API: enables Game Center on the app record, then creates the
# two leaderboards and seven achievements whose IDs the app already reports
# to (GameCenter.ID). Idempotent: existing vendorIdentifiers are skipped.
require "jwt"
require "json"
require "net/http"
require "openssl"
require "uri"

KEY = JSON.parse(File.read(File.expand_path("~/.appstoreconnect/asc_api_key.json")))
BUNDLE_ID = "com.couchsuite.nine"

def token
  now = Time.now.to_i
  payload = { iss: KEY.fetch("issuer_id"), iat: now, exp: now + 900, aud: "appstoreconnect-v1" }
  key = OpenSSL::PKey.read(KEY.fetch("key"))
  JWT.encode(payload, key, "ES256", { kid: KEY.fetch("key_id") })
end

def request(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
  req = klass.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = "application/json"
  req.body = JSON.generate(body) if body
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  parsed = res.body && !res.body.empty? ? JSON.parse(res.body) : {}
  unless res.code.to_i.between?(200, 299)
    raise "#{method.to_s.upcase} #{path} -> #{res.code}: #{JSON.generate(parsed["errors"] || parsed)[0, 600]}"
  end
  parsed
end

def paged(path)
  items = []
  next_path = path
  while next_path
    page = request(:get, next_path)
    items.concat(page["data"] || [])
    next_url = page.dig("links", "next")
    next_path = next_url && URI(next_url).then { |u| "#{u.path}?#{u.query}" }
  end
  items
end

# 1. App record.
app = request(:get, "/v1/apps?filter[bundleId]=#{BUNDLE_ID}")["data"].first
abort "No ASC app record for #{BUNDLE_ID} — create the app in App Store Connect first." unless app
puts "app: #{app.dig("attributes", "name")} (#{app["id"]})"

# 2. Game Center detail (creating it enables Game Center for the app).
detail = begin
  request(:get, "/v1/apps/#{app["id"]}/gameCenterDetail")["data"]
rescue => e
  nil
end
if detail
  puts "gameCenterDetail: exists (#{detail["id"]})"
else
  detail = request(:post, "/v1/gameCenterDetails", {
    data: {
      type: "gameCenterDetails",
      relationships: { app: { data: { type: "apps", id: app["id"] } } },
    },
  })["data"]
  puts "gameCenterDetail: created (#{detail["id"]})"
end
detail_id = detail["id"]

# 3. Leaderboards.
LEADERBOARDS = [
  { vendor: "com.couchsuite.nine.points", ref: "Total Points", name: "Total Points" },
  { vendor: "com.couchsuite.nine.streak", ref: "Best Daily Streak", name: "Best Daily Streak" },
]

existing_lb = paged("/v1/gameCenterDetails/#{detail_id}/gameCenterLeaderboards?fields[gameCenterLeaderboards]=vendorIdentifier&limit=50")
  .to_h { |lb| [lb.dig("attributes", "vendorIdentifier"), lb["id"]] }

LEADERBOARDS.each do |spec|
  if existing_lb[spec[:vendor]]
    puts "leaderboard #{spec[:vendor]}: exists"
    next
  end
  lb = request(:post, "/v1/gameCenterLeaderboards", {
    data: {
      type: "gameCenterLeaderboards",
      attributes: {
        defaultFormatter: "INTEGER",
        referenceName: spec[:ref],
        vendorIdentifier: spec[:vendor],
        submissionType: "BEST_SCORE",
        scoreSortType: "DESC",
      },
      relationships: { gameCenterDetail: { data: { type: "gameCenterDetails", id: detail_id } } },
    },
  })["data"]
  request(:post, "/v1/gameCenterLeaderboardLocalizations", {
    data: {
      type: "gameCenterLeaderboardLocalizations",
      attributes: { locale: "en-US", name: spec[:name] },
      relationships: { gameCenterLeaderboard: { data: { type: "gameCenterLeaderboards", id: lb["id"] } } },
    },
  })
  puts "leaderboard #{spec[:vendor]}: created + en-US localization"
end

# 4. Achievements. GC points: <=100 each, <=1000 total (these total 210).
ACHIEVEMENTS = [
  { vendor: "com.couchsuite.nine.solve.first", ref: "First Solve", points: 10,
    name: "First Light", before: "Solve your first board.", after: "You solved your first board." },
  { vendor: "com.couchsuite.nine.solve.ten", ref: "Ten Solves", points: 25,
    name: "Ten Deep", before: "Solve ten boards.", after: "Ten boards solved." },
  { vendor: "com.couchsuite.nine.solve.fifty", ref: "Fifty Solves", points: 50,
    name: "Fifty Deep", before: "Solve fifty boards.", after: "Fifty boards solved." },
  { vendor: "com.couchsuite.nine.sharp.first", ref: "First Sharp Solve", points: 25,
    name: "Sharpened", before: "Solve a Sharp board.", after: "You conquered a Sharp board." },
  { vendor: "com.couchsuite.nine.streak.seven", ref: "Seven-Day Streak", points: 25,
    name: "Week of Nines", before: "Solve the daily seven days in a row.", after: "Seven dailies in a row." },
  { vendor: "com.couchsuite.nine.streak.thirty", ref: "Thirty-Day Streak", points: 50,
    name: "Month of Nines", before: "Solve the daily thirty days in a row.", after: "Thirty dailies in a row." },
  { vendor: "com.couchsuite.nine.swift", ref: "Speed Solve", points: 25,
    name: "Swift Nine", before: "Solve a board in under five minutes.", after: "Solved in under five minutes." },
]

existing_ach = paged("/v1/gameCenterDetails/#{detail_id}/gameCenterAchievements?fields[gameCenterAchievements]=vendorIdentifier&limit=50")
  .to_h { |a| [a.dig("attributes", "vendorIdentifier"), a["id"]] }

ACHIEVEMENTS.each do |spec|
  if existing_ach[spec[:vendor]]
    puts "achievement #{spec[:vendor]}: exists"
    next
  end
  ach = request(:post, "/v1/gameCenterAchievements", {
    data: {
      type: "gameCenterAchievements",
      attributes: {
        points: spec[:points],
        referenceName: spec[:ref],
        repeatable: false,
        showBeforeEarned: true,
        vendorIdentifier: spec[:vendor],
      },
      relationships: { gameCenterDetail: { data: { type: "gameCenterDetails", id: detail_id } } },
    },
  })["data"]
  request(:post, "/v1/gameCenterAchievementLocalizations", {
    data: {
      type: "gameCenterAchievementLocalizations",
      attributes: {
        locale: "en-US",
        name: spec[:name],
        beforeEarnedDescription: spec[:before],
        afterEarnedDescription: spec[:after],
      },
      relationships: { gameCenterAchievement: { data: { type: "gameCenterAchievements", id: ach["id"] } } },
    },
  })
  puts "achievement #{spec[:vendor]}: created + en-US localization"
end

puts "done."
