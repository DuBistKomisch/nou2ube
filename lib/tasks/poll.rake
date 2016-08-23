require 'signet/oauth_2/client'
require 'google/apis/youtube_v3'

namespace :nou2ube do
  desc 'Poll for new videos'
  task poll: :environment do
    puts "getting subscriptions for #{User.count} users"
    channel_count = Channel.count
    subscription_count = Subscription.count
    User.all.each do |user|
      # create authorization
      authorization = Signet::OAuth2::Client.new(
        authorization_uri: 'https://accounts.google.com/o/oauth2/auth',
        token_credential_uri: 'https://www.googleapis.com/oauth2/v3/token',
        client_id: ENV['GOOGLE_CLIENT_ID'],
        client_secret: ENV['GOOGLE_CLIENT_SECRET'],
        refresh_token: user.refresh_token
      )
      authorization.refresh!
      user.refresh_token = authorization.refresh_token
      user.save

      # create authorized service
      youtube = Google::Apis::YoutubeV3::YouTubeService.new
      youtube.authorization = authorization

      # get subscriptions
      items = youtube.fetch_all do |token|
        youtube.list_subscriptions('snippet', mine: true, max_results: 50, page_token: token)
      end
      items.each do |item|
        channel = Channel.find_or_initialize_by(api_id: item.snippet.resource_id.channel_id)
        channel.title = item.snippet.title
        channel.thumbnail = item.snippet.thumbnails.default.url
        channel.checked_at = DateTime.now if channel.new_record?
        channel.save

        Subscription.find_or_create_by(user: user, channel: channel)
      end
      # remove subscriptions which no longer exist
      Subscription.joins(:channel, :user)
        .where('users.id = ? AND channels.api_id NOT IN (?)', user.id,
               items.map{ |item| item.snippet.resource_id.channel_id })
        .destroy_all
    end
    puts "added #{Channel.count - channel_count} channels, #{Subscription.count - subscription_count} subscriptions"

    # create anonymous service
    youtube = Google::Apis::YoutubeV3::YouTubeService.new
    youtube.key = ENV['GOOGLE_API_KEY']

    # get uploads_id if missing
    channels = Channel.where(uploads_id: '')
    puts "getting uploads_id for #{channels.count} channels"
    if channels.count > 0
      youtube.batch do |youtube|
        channels.each do |channel|
          youtube.list_channels('snippet,contentDetails', id: channel.api_id) do |result, err|
            item = result.items.first
            channel.uploads_id = item.content_details.related_playlists.uploads
            channel.save
          end
        end
      end
    end

    # get new videos
    puts "getting new videos for #{Channel.count} channels"
    video_count = Video.count
    item_count = Item.count
    to_check = Channel.all.to_a.clone
    to_check_token = {}
    to_check_latest = {}
    while to_check.count > 0 do
      youtube.batch do |youtube|
        to_check.each do |channel|
          youtube.list_playlist_items('snippet', playlist_id: channel.uploads_id, max_results: 2, page_token: to_check_token[channel.api_id]) do |result, err|
            to_check_token[channel.api_id] = result.next_page_token
            to_check_latest[channel.api_id] = channel.checked_at if to_check_latest[channel.api_id].nil?

            stop = false
            result.items.each do |item|
              published_at = item.snippet.published_at.to_datetime
              unless published_at > channel.checked_at
                stop = true
                break
              end

              to_check_latest[channel.api_id] = published_at if published_at > to_check_latest[channel.api_id]

              video = Video.find_or_create_by(api_id: item.snippet.resource_id.video_id)  do |video|
                video.channel = channel
                video.published_at = published_at
                video.title = item.snippet.title
                video.thumbnail = item.snippet.thumbnails.default.url
              end

              channel.users.each do |user|
                Item.find_or_create_by(subscription: Subscription.find_by(user: user, channel: channel), video: video)
              end
            end

            if stop
              to_check.delete channel
              channel.checked_at = to_check_latest[channel.api_id]
              channel.save
            end
          end
        end
      end
    end
    puts "added #{Video.count - video_count} videos, #{Item.count - item_count} items"

    # get duration if missing
    videos = Video.where(duration: 0)
    puts "getting duration for #{videos.count} videos"
    if videos.count > 0
      youtube.batch do |youtube|
        videos.each do |video|
          youtube.list_videos('contentDetails', id: video.api_id) do |result, err|
            item = result.items.first
            captures = item.content_details.duration.match(/PT((\d+)H)?((\d+)M)?((\d+)S)?/).captures
            video.duration = (captures[0].nil? ? 0 : captures[1].to_i.hours) + (captures[2].nil? ? 0 : captures[3].to_i.minutes) + (captures[4].nil? ? 0 : captures[5].to_i.seconds)
            video.save
          end
        end
      end
    end

    # cull leftover records
    video_count = Video.count
    Video.where('(SELECT COUNT(*) FROM items WHERE items.video_id = videos.id) = 0').destroy_all
    channel_count = Channel.count
    Channel.where('(SELECT COUNT(*) FROM subscriptions WHERE subscriptions.channel_id = channels.id) = 0').destroy_all
    puts "culled #{video_count - Video.count} videos, #{channel_count - Channel.count} channels"
  end
end
