require 'nokogiri'
require 'open-uri'
require 'date'

def get_game_ids(date)
  url = "http://sports.yahoo.com/mlb/scoreboard?d=#{date}"

  doc = Nokogiri::HTML(open(url))
  game_ids = []

  doc.css('a.yspmore').each do |link|
    if link.content == 'Box Score'
      link.attributes['href'].value =~ /\/mlb\/boxscore\?gid=(\d*)/
      game_ids << $1
    end
  end
  
  game_ids
end


def get_game_data(game_id, date)
  url = "http://sports.yahoo.com/mlb/boxscore?gid=#{game_id}"
  team = ''
  home_team = ''
  away_team = ''
  player_stats = Hash.new(nil)
  game_data = Hash.new(nil)

  doc = Nokogiri::HTML(open(url))
  nbsp = Nokogiri::HTML("&nbsp;").text  # this is to account for '&nbsp;'' problems with the source HTML

  batter_table_headers_read_write = ['AB', 'R', 'H', 'RBI', 'HR', 'BB', 'K', 'SB', 'LOB', 'Season Avg']
  # pitcher table needs different read/write headers because of overlap of some
  # of the pitcher table headers with that of the batter tables but with different
  # meaning (i.e., H, R, BB, K, HR)
  pitcher_table_headers_read = ['IP', 'H', 'R', 'ER', 'BB', 'K', 'HR', 'WHIP', 'Season ERA']
  pitcher_table_headers_write = ['IP', 'H-p', 'R-p', 'ER', 'BB-p', 'K-p', 'HR-p', 'WHIP', 'Season ERA']

  p url

  unless game_postponed?(doc)    # only get game data if game was not postponed
    tables = doc.css('table.yspwhitebg')

    tables[1..3].each do |table|   # only use tables 2 through 4, the others are irrelevant
      headers = []

      table.css('tr')[1].css('td').each do |col|  # get the headers from the second row of the table    
        # p col.text
        # p col.inner_html
        headers << col.inner_html
      end

      if headers[1...-1] == batter_table_headers_read_write[0...-1] # only compare the 2nd to the 2nd to last element
                                                                    # to skip the initial '&nbsp;'' and last 'Season Avg&nbsp;' columns
        batter_table = true
        p 'batter table found'

        team = table.css('tr')[0].text.gsub(nbsp, "").strip  # get the team name from the first row

        if away_team.empty?
          away_team = team
        else
          home_team = team
        end

        table.css('tr')[2...-1].each do |row|  # skip team, header, and 'Totals' rows
          # player = Hash.new(nil)

          # clean up the name & position data and store in separate variables
          name_position = row.css('td')[0].text.gsub(nbsp, "").strip
          name_position = name_position.split(" ")

          position = name_position.pop
          name = name_position.join(" ")

          # create a hash to store stats for each player
          player_stats[name] = Hash.new(nil)
          player_stats[name]['team'] = team
          player_stats[name]['home_or_away'] = team == away_team ? 'away' : 'home' 
          player_stats[name]['position'] = position

          row.css('td')[1...-1].each_with_index do |col, index|  # skip last col because it is empty
            player_stats[name][batter_table_headers_read_write[index]] = col.text
          end
        end

      elsif headers[1...-1] == pitcher_table_headers_read[0...-1] # only compare the 2nd to the 2nd to last element
                                                                  # to skip the initial '&nbsp;'' and last 'Season ERA&nbsp;' columns
        p 'pitcher table found'

        table.css('tr').each do |row|
          if row['class'] == 'yspsctbg'
            team = row.text.gsub(nbsp, "").strip  # get the team name from the first row

          elsif row['class'] == 'ysprow1' || row['class'] == 'ysprow2'
            name_win_loss_record = row.css('td')[0].text.gsub(nbsp, '').strip
            name_win_loss_record = name_win_loss_record.split(' ')

            name = name_win_loss_record[0..1].join(' ')

            if player_stats.has_key?(name)  # if player is already in the hash, just add new data to their hash
              # p 'player exists'
              row.css('td')[1...-1].each_with_index do |col, index| # skip last col because it is empty
                player_stats[name][pitcher_table_headers_write[index]] = col.text
              end
            else                            # else create a new entry in the hash with the new stats
              # p 'found a pitcher that did not bat'

              player_stats[name] = Hash.new(nil)  
              player_stats[name]['team'] = team
              player_stats[name]['home_or_away'] = team == away_team ? 'away' : 'home'
              player_stats[name]['position'] = 'p'

              row.css('td')[1...-1].each_with_index do |col, index| # skip last col because it is empty
                player_stats[name][pitcher_table_headers_write[index]] = col.text
              end
            end
          end
        end
      else
        p '-' * 40 + 'ERROR found non-batter and non-pitcher table' + '-' * 40
      end
    end
  
    game_data['game_id'] = game_id
    game_data['date'] = date
    game_data['home_team'] = home_team
    game_data['away_team'] = away_team
    game_data['player_stats'] = player_stats

    # player_stats
  else
    p '-' * 40 + 'ERROR game postponed' + '-' * 40
  end

  game_data
end

def game_postponed?(doc)  # if the headline has the word "post", as in "postponed" or "Postponed", game was postponed
  doc.css('td.yspsctnhdln').text.strip =~ /post/i ? true : false
end

def write_to_file(game_data)
  unless game_data.empty?    # if game_data is empty that means game was postponed, don't write the file
    game_id = game_data['game_id']
    game_date = game_data['date']
    home_team = game_data['home_team']
    away_team = game_data['away_team']

    File.open("stats/#{game_id}-#{game_date}-#{away_team}_vs_#{home_team}.txt", "w") do |file|
      headers = ['game id', 'date', 'name', 'position', 'team', 'home_or_away',
                 'AB', 'R', 'H', 'RBI', 'HR', 'BB', 'K', 'SB', 'LOB', 'Season Avg',
                 'IP', 'H-p', 'R-p', 'ER', 'BB-p', 'K-p', 'HR-p', 'WHIP', 'Season ERA']

      file.puts headers.join(', ')
      
      game_data['player_stats'].each do |name, stats|
        line = [game_id, game_date, name]

        headers[3..-1].each do |stat|  # skip first element because name is the key and already in the line array
          line << stats[stat]
        end

        file.puts line.join(', ')
      end
    end

    p "#{game_id}-#{game_date}-#{away_team}_vs_#{home_team}.txt generated"
  else
    p '-' * 40 + 'Game postponed, no file generated' + '-' * 40
  end
end

def runner(start_date, end_date = start_date)
  dates = get_dates(start_date, end_date)

  dates.each do |date|
    game_ids = get_game_ids(date)
  
    game_ids.each do |game_id|
      game_data = get_game_data(game_id, date)
      write_to_file(game_data)
      sleep 5                                     # add delay
    end

  end
end

def get_dates(start_date, end_date = start_date)
  (Date.parse(start_date)..Date.parse(end_date)).to_a
end

# scripts ----------------------------------------------------------------------

# p get_game_ids('2013-05-27')
# p game_data = get_game_data(330527120)
# write_to_file('1234', '05-27-2013', player_stats)

# 2013 MLB Season started on 2013-03-31 and is scheduled to end on 2013-09-29.

# runner('2013-03-31', '2013-04-30')
# runner('2013-05-01', '2013-05-31')
# runner('2013-05-16', '2013-05-31')
runner('2013-06-01', '2013-06-04')
