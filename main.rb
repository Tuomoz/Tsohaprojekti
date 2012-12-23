# encoding: UTF-8
require 'sinatra'
require "sinatra/reloader"
require "sequel"
require "haml"
require 'rack-flash'


DB = Sequel.connect('postgres://tuokarkk@localhost:1234')
use Rack::Flash

configure do
  enable :sessions

end

helpers do
  def logged_in?
    session[:user] != nil
  end

  def check_login
    unless logged_in?
      flash[:msg_type] = :info
      flash[:msg_content] = "Sinun on ensin kirjauduttava sisään!"
      redirect "/"
    end
  end

  def get_nav_class path
    if request.path_info == path
      "active"
    else
      ""
    end
  end

  def get_username_from_id id
    user = DB.fetch("SELECT username FROM users WHERE id = ?", id).first
    return user[:username]
  end

end

# Pääsivu
get "/" do
  if params.has_key?("logout")
    session.clear
  end
  haml :index
end

# Kirjautuminen sisään. Tarkistetaan, vastaavatko käyttäjänimi ja salasana toisiaan.
# Tallennetaan käyttäjää vastaava id sivuston käyttämään evästeeseen.
post "/login" do
  user = DB.fetch("SELECT id FROM users WHERE username = ? AND password = ?", 
                  params[:username], params[:password]).first

  if user
    session[:user] = user[:id]
    redirect "/user"
  else
    flash[:msg_type] = :error
    flash[:msg_content] = "Käyttäjänimi tai salasana on väärin!"
    redirect "/"
  end
end

# Käyttäjäsivu, jolta näkyy käyttäjän sopimat ja sopimattomat ajat. Samalta sivulta
# voi myös lisätä uusia aikoja. Tiedot ajoista etsitään tietokannasta kahteen
# hajautustauluun.
get "/user" do
  check_login

  # Ajan mittaaminen vain suorituskyvyn vertailemiseksi
  beginning_time = Time.now

  times_without_pair = DB.fetch("SELECT *
                                 FROM times WHERE user_id = ? AND 
                                 pair_time_id IS NULL
                                 ORDER BY date, time_start", session[:user])

  times_with_pair = DB.fetch("SELECT t.*,
                              GREATEST (t.time_start, l.time_start) as time_start, 
                              LEAST (t.time_end, l.time_end) as time_end,
                              username as pair_username
                              FROM times t, times l, users u 
                              WHERE t.pair_time_id = l.id
                              AND t.user_id = ? AND l.user_id = u.id
                              ORDER BY t.date, t.time_start", session[:user])

  haml :user, locals: {times_without_pair: times_without_pair, 
                       times_with_pair: times_with_pair, 
                       beginning_time: beginning_time}
    
end

# Uuden ajan lisääminen. Aluksi tarkistetaan löytyykö käyttäjältä jo aikaisempi aika,
# joka menee uuden ajan kanssa päällekkäin. Tämän jälkeen etsitään muiden käyttäjien
# vapaista ajoista sopivaa paria ja jos sellainen löytyy, laitetaan kumpikin aika
# viittaamaan toiseen pair_time_id -kentän avulla. Jos sopivaa paria ei löytynyt,
# lisätään uusi aika normaalisti kantaan ja jätetään pair_time_id -kenttä tyhjäksi.
post "/addtime" do
  check_login

  # TODO: Aikojen ja päivämäärän oikeellisuuden tarkistus kokonaan
  time_check = /^\d{2}:\d{2}$/
  unless params[:time_start] =~ time_check && params[:time_end] =~ time_check
    flash[:status_msg] = :bad_params
    redirect "/user"
  end

  # Löytyykö jo samalta aikaväliltä vanhaa aikaa?
  overlapping_time = DB.fetch("SELECT id FROM times WHERE
                          user_id = ? AND
                          date = ? AND
                          (? BETWEEN time_start AND time_end OR 
                           ? BETWEEN time_start AND time_end)",
                          session[:user], params[:date], params[:time_end], params[:time_start]).first

  if (overlapping_time)
    flash[:status_msg] = :overlapping_times
    redirect "/user"
  end
  
  # Löytyykö muiden käyttäjien ajoista sopivaa paria? Sopivat ajat etsitään siten, että
  # tapahtumalle jäisi aikaa vähintään kaksi tuntia.
  found_pair = DB.fetch("SELECT id
                         FROM times
                         WHERE pair_time_id IS NULL AND
                         date = ? AND
                         time_end - time '02:00' >= ? AND
                         time_start <= ? - time '02:00' AND
                         location = ?",
                         params[:date], params[:time_start], params[:time_end], params[:location]).first

  if (found_pair)
    insert_ds = DB["INSERT INTO times (date, time_start, time_end, user_id, pair_time_id, location, conversation_id)
                    VALUES (?, ?, ?, ?, ?, ?, nextval('conversation_id_seq')) returning id", 
                  params[:date], params[:time_start], params[:time_end], session[:user], 
                  found_pair[:id], params[:location]]

    update_ds = DB["UPDATE times SET pair_time_id = ?, conversation_id = currval('conversation_id_seq') WHERE id = ?",
                  insert_ds[:values][:id], found_pair[:id]]
    update_ds.update
    flash[:status_msg] = :pair_found

  else
    insert_ds = DB["INSERT INTO times (date, time_start, time_end, user_id, location)
                    VALUES (?, ?, ?, ?, ?)",
                  params[:date], params[:time_start], params[:time_end], session[:user], params[:location]]
    flash[:status_msg] = :time_added
    insert_ds.insert
  end

  redirect "/user"
end

# Vanhan ajan poistaminen. Jos aikaan liittyy pari, poistetaan parin ajasta viittaus poistettavaan aikaan
# sekä keskusteluun. Lisäksi poistetaan myös keskusteluun liittyvät viestit. Tämä tulee varmasti muuttumaan,
# sillä oikeassa käytössä vanhojen viestien ainakin osittainen säilyttäminen olisi toivottavaa.
get "/deletetime/:timeid" do
  check_login

  time = DB.fetch("SELECT * FROM times WHERE id = ?", params[:timeid]).first
  unless time
    redirect "/user"
  end

  if time[:pair_time_id] != nil
    update_ds = DB["UPDATE times SET pair_time_id = NULL, conversation_id = NULL WHERE id = ?",
                  time[:pair_time_id]]
    update_ds.update
    delete_ds = DB["DELETE FROM messages WHERE conversation_id = ?", time[:conversation_id]]
    delete_ds.delete
  end

  delete_ds = DB["DELETE FROM times WHERE id = ? AND user_id = ?", params[:timeid], session[:user]]
  delete_ds.delete
  redirect "/user"
end

# Yhden ajan tarkkojen tietojen haku. Näytetään aikojen ja päivämäärän lisäksi aikaan liittyvä
# keskustelu. Kyseisiä tietoja ei näytetä omalla sivullaan, vaan eräänlaisessa ikkunassa
# käyttäjä-sivulla.
get "/time/:timeid" do
  check_login

  if params[:unpaired]
    time = DB.fetch("SELECT *
                     FROM times WHERE user_id = ? AND 
                     id = ?", session[:user], params[:timeid]).first
    messages = nil
  else
    time = DB.fetch("SELECT t.*,
                     GREATEST (t.time_start, l.time_start) as time_start, 
                     LEAST (t.time_end, l.time_end) as time_end,
                     username as pair_username
                     FROM times t, times l, users u 
                     WHERE t.pair_time_id = l.id AND t.user_id = ?
                     AND t.id = ? AND l.user_id = u.id", session[:user], params[:timeid]).first

    messages = DB.fetch("SELECT *, username FROM messages, users WHERE conversation_id = ?
                       AND messages.user_id = users.id
                       ORDER BY timestamp DESC", time[:conversation_id])
  end
  haml :time, locals: {time: time, messages: messages}, layout: !request.xhr? # Ajax ftw!
end

# Uuden viestin lisääminen.
post "/addmessage" do
  check_login

  conversation_id = DB.fetch("SELECT conversation_id FROM times WHERE id = ? AND user_id = ?",
                            params[:time_id], session[:user]).first
  unless conversation_id
    redirect "/user"
  end

  insert_ds = DB["INSERT INTO messages (conversation_id, timestamp, message, user_id)
                  VALUES (?, CURRENT_TIMESTAMP, ?, ?)",
                conversation_id[:conversation_id], params[:message], session[:user]]
  insert_ds.insert
  ":)"
end

# Uuden käyttäjän rekisteröiminen. Uutta käyttäjää ei luoda, jos annettu käyttäjänimi
# on jo käytässö aikaisemmin.
post "/newuser" do
  user = DB.fetch("SELECT id FROM users WHERE username = ?", params[:username]).first
  if user
    flash[:msg_type] = :error
    flash[:msg_content] = "Käyttäjänimi on jo varattu!"
    redirect "/"
  end

  insert_ds = DB["INSERT INTO users (username, password) VALUES (?, ?)",
                params[:username], params[:password]]
  insert_ds.insert
  flash[:msg_type] = :success
  flash[:msg_content] = "Käyttäjä luotu onnistuneesti!"
  redirect ="/"
end

get "/all_times" do
  check_login
  times = DB.fetch("SELECT * FROM times WHERE pair_time_id IS NULL
                    ORDER BY date DESC, time_start DESC")
  haml :all_times, locals: {times: times}
end