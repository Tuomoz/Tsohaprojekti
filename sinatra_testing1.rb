require 'sinatra'
require "sinatra/reloader"
require "sequel"

configure do
  enable :sessions
end
  DB = Sequel.connect('postgres://tuokarkk@localhost:1234')
get '/' do  
  users = DB.fetch("SELECT * FROM users")
  "users: #{users.count}"
end

get '/hello/:name' do  
  params[:name]  
end

get '/form' do  
  erb :testform 
end

post '/form' do  
  "You said '#{params[:message]}'"  
end

get '/database' do
	DB = Sequel.connect('postgres://tuokarkk:a49c3d3d3315c8f4@localhost:1234')

	users = DB[:users]

	"users count: #{users.count}" 
end

post '/login' do
  "Username: #{params[:username]} Password: #{params[:password]}"

  DB = Sequel.connect('sqlite://testdb')

  user = DB.fetch("SELECT id FROM users WHERE username = ? AND password = ?", 
                  params[:username], params[:password]).first

  if user
    session[:user] = user[:id]
  else
    "OHNOEZ! :((("
  end
end