

yesNo = (v) -> if v then "yes" else "no"
secs = 1000
mins = 60 * secs
hours = 60 * mins
days = 24 * hours
weeks = 7 * days
formatUptime = (ms) ->
	w = Math.floor(ms / weeks)
	t = ms - (w * weeks)
	d = Math.floor(t / days)
	t = t - (d * days)
	h = Math.floor(t / hours)
	t = t - (h * hours)
	m = Math.floor(t / mins)
	t = t - (m * mins)
	s = Math.floor(t / secs)
	t = t - (s * secs)
	ret = $("w", "d", "h", "m", "s")
		.weave($ w, d, h, m, s)
		.join('')
		.replace(/^(0[wdhm])*/,'')
	ret

module.exports = { yesNo, formatUptime }
