
console.log("PORT:", process.env.PORT)
if(parseInt(process.env.PORT) % 1000 == 3)
	process.exit(3)
