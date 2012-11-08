require 'sinatra'
require "sinatra/reloader"
require "sequel"

get '/' do  
  "Hello, World!"  
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
	DB = Sequel.connect('sqlite://testdb')

	users = DB[:users]

	"users count: #{users.count}" 
end

post '/login' do
  "Username: #{params[:username]} Password: #{params[:password]}"
end