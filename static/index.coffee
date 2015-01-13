

uptime_parse = (uptime) ->
	u = uptime.split(':')
	u[0] * 3600 + u[1] * 60 + +u[2]
uptime_format = (u) ->
	s = ((m = ((h = u/3600) % 1) * 60) % 1) * 60
	h = Math.floor h
	m = Math.floor m
	s = Math.round s
	$(h,m,s).map((v) ->
		$.padLeft String(v), 2, "0"
	).join ":"

dynamic_uptime_interval = $.interval 1000, ->
	$("td.uptime").each (node) ->
		node.textContent = uptime_format(uptime_parse(node.textContent) + 1)

$(document).ready ->
	this_port = parseInt (location.port or 80), 10
	server_row = (process) ->
		$.synth "tr.proc td '#{process.ports.join(",")}' " +
			"+ td '#{process.pid}' + td.uptime '#{process.uptime}' + td '#{process.command}' " +
			"+ td '#{$.commaize process.rss} kb' + td[align=center] '#{process.cpu.toFixed(2)} %' " +
			"+ td a[href=/reload/#{process.pid}] 'Restart'"
	worker_row = (process) ->
		$.synth "tr.proc td '#{process.pid}' " +
			"+ td.uptime '#{process.uptime}' " +
			"+ td '#{process.command}' + td '#{$.commaize process.rss} kb' " +
			"+ td[align=center] '#{process.cpu.toFixed 2} %' " +
			"+ td a[href=/reload/#{process.pid}] 'Restart'"
	visit_server = (process, table) ->
		unless table
			table = $.synth "table.tree"
			table.append $.synth "tr th 'Port(s)' " +
				"+ th 'PID' + th 'Uptime' + th 'Command' + th 'RAM' + th 'CPU' + th 'Action'"
		if process.ports.length > 0 and not (this_port in process.ports)
			table.append server_row process
		for child in process.children
			visit_server(child, table)
		table

	$("td.servers").append visit_server(window.tree)


	visit_worker = (process, table) ->
		unless table
			table = $.synth "table.tree"
			table.append $.synth "tr " +
				"+ th 'PID' + th 'Uptime' + th 'Command' + th 'RAM' + th 'CPU' + th 'Action'"
		if process.ports.length is 0 and process.children.length is 0 and (process.command.indexOf("ps -eo uid,") is -1)
			table.append worker_row process
		for child in process.children
			visit_worker(child, table)
		table

	$("td.workers").append visit_worker(window.tree)

