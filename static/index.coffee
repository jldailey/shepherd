
$(document).ready ->
	this_port = parseInt (location.port or 80), 10
	visit_server = (process, table) ->
		unless table
			table = $.synth "table.tree"
			table.append $.synth "tr th 'Port(s)' " +
				"+ th 'PID' + th 'Command' + th 'RAM' + th 'CPU' + th 'Action'"
		if process.ports.length > 0 and not (this_port in process.ports)
			row = $.synth "tr.proc td '#{process.ports.join(",")}' " +
				"+ td '#{process.pid}' + td '#{process.command}' " +
				"+ td '#{$.commaize process.rss} kb' + td[align=center] '#{process.cpu.toFixed(2)} %' " +
				"+ td a[href=/reload/#{process.pid}] 'Restart'"
			table.append row
		for child in process.children
			visit_server(child, table)
		table

	$("td.servers").append visit_server(window.tree)

	visit_worker = (process, table) ->
		unless table
			table = $.synth "table.tree"
			table.append $.synth "tr " +
				"+ th 'PID' + th 'Command' + th 'RAM' + th 'CPU' + th 'Action'"
		if process.ports.length is 0 and process.children.length is 0 and (process.command.indexOf("ps -eo uid,") is -1)
			row = $.synth "tr.proc td '#{process.pid}' " +
				"+ td '#{process.command}' + td '#{$.commaize process.rss} kb' " +
				"+ td[align=center] '#{process.cpu.toFixed 2} %' " +
				"+ td a[href=/reload/#{process.pid}] 'Restart'"
			table.append row
		for child in process.children
			visit_worker(child, table)
		table

	$("td.workers").append visit_worker(window.tree)

