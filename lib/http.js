(function() {

	var $ = require('bling'),
		Express = require('express'),
		Http = require('http'),
		Git = require('./git'),
		toBr = function(s) { return String(s)
			.replace(/(?:\n|\r)/g,"<br>")
			.replace(/\t/g,"    ")
		},
		log = $.logger("[http]"),
		app = Express()

	app.get("/", function(req, res) {
		res.statusCode = 200;
		res.contentType = "text/html";
		res.end("<html>"
		+ "<head>"
		+ "<link rel=icon href='data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBwgHBgkIBwgKCgkLDRYPDQwMDRsUFRAWIB0iIiAdHx8kKDQsJCYxJx8fLT0tMTU3Ojo6IyQ/RD84Qz02OjcBCgoKDQwNGBAQFywcHCQ3LDQsKyw1LDQsKyssLCwsLCwsKysyKysuKywrLCwrKywrKysrKyssKysrKysrKysrK//AABEIADAAMAMBIgACEQEDEQH/xAAZAAADAQEBAAAAAAAAAAAAAAAEBQYDAQf/xAAxEAACAQMDAQYFAgcAAAAAAAABAgMABBEFEiExBhMiQVFhFDKBkcFx8DM0QlKSodH/xAAWAQEBAQAAAAAAAAAAAAAAAAABAAL/xAAYEQEBAQEBAAAAAAAAAAAAAAAAAREhEv/aAAwDAQACEQMRAD8A9k1O8+Dtwwx3kjrHHnpuJ/ZpVPeQxeK6umuXLEJHgKowcZwPzQfaHUEu2ls2mi2rJtSFBmV3BxwfLnjpQVpJNBYxdzbGWXagdUwSMsQzMSR4VxyRk+1Z9HDN9Zt4D3sDyIy9Yt/gf1wD+KZtrtlvIjaSZR8zxRlgP+/SpG9PxMam5ijJSZVAWUPvQtgElQMbhzt6jPWnh7NQJKTb3EkKA5Tail0Ps2M07Vh7a6hZ3n8tcxyH+0Nz9utFUhudFtbuIfEDM4H8dF2sT6nHFYaFrEqzjTNQU96jGNJR0YjyNIUexc52jPriplI7KXUrmxu4A8guGliV48gAgHg+/Jqopbreni+spBHlblVJikQ7WB9Mj1os0y4n9at8KsNpDlmlGwJgc+v3qmGcDdjd549akdGEcDrdFpHuh4HM7lmB8wM9KftqYz4YTj3aqTFaPYhQWYgAdSamCk15q06WqNzImJscIRzk/St9T1F3G1I2dwpZYU6nAySaO7KRssN27uHd5QSQMf0KfzSD6uEgDJ4rtZXCM6eDrUkreJaTa/L3yboizb8EjOETjI9zmljGGOfJmuBF38gwsp+QAEDn9aCEXaJ9feGeznW2NzIxcxDbsIIBDfRaDtL2e91dNH7hQY7iYMRnd0PJHpwKOkVoHai2t7uR5EldZ7dmLuPJT0+x/wBVQdg9at743FtHvVgkcmHXGTt2nH+IoKy7HwROStsg3ZB48j1FUGhdnrTSSzWtskLP8zDqfb9KsD//2Q=='>"
		+ "</head><body>"
		+ "Welcome to the <b>Shepherd</b>."
		+ "</body>")
	})

	// allow other modules to inject routes by publishing them locally
	$.subscribe('http-route', function(method, path, handler) {
		method = method.toLowerCase()
		log("adding published route:", method, path)
		app[method].call(app, path, handler)
	})

	server = Http.createServer(app)

	$.extend(module.exports, {
		toBr: toBr, // a helpful utility
		listen: function(port) {
			server.listen(port, function(err) {
				if( err != null ) log("failed to listen on port:",port,"error:",err)
				else log("listening on master port:", port)
			})
		}
	})

})(this)
