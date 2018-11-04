function setupCharts()
{
	var shots_element = document.getElementById("shots-canvas");
	if (shots_element != null)
	{
		var shots_ctx = shots_element.getContext("2d");
		window.shots_chart = new Chart(shots_ctx, {
			type: 'horizontalBar',
			data: {
				labels: [],
				datasets: [{
					borderColor: [],
					backgroundColor: [],
					borderWidth: 2,
					fill: false,
					data: []
				}]
			},
			options: {
				responsive: true,
				maintainAspectRatio: false,
				title: {
					display: false,
				},
				legend: {
					display: false,
				},
				tooltips: {
					mode: 'index',
					intersect: true,
					callbacks: {
						label: function(tooltipItem, data) {
							return Math.abs(tooltipItem.xLabel).toFixed(3);
						},
					},
				},
				scales: {
					xAxes: [{
						scaleLabel: {
							display: true,
							labelString: 'Shots',
						},
						ticks: {
							beginAtZero: true,
						},
					}],
				}
			}
		});
	}
	
	var cdf_element = document.getElementById("cdf-canvas");
	if (cdf_element != null)
	{
		var cdf_ctx = cdf_element.getContext("2d");
		window.cdf_chart = new Chart(cdf_ctx, {
			type: 'scatter',
			data: {
				datasets: [{
					showLine: true,
					borderColor: 'rgb(255, 99, 132)',
					backgroundColor: 'rgba(255, 99, 132, 0.2)',
					borderWidth: 2,
					pointRadius: 1,
					fill: "origin",
					data: [],
				}],
			},
			options: {
				responsive: true,
				maintainAspectRatio: false,
				title: {
					display: false,
				},
				legend: {
					display: false,
				},
				tooltips: {
					mode: 'index',
					intersect: false,
					callbacks: {
						label: function(tooltipItem, data) {
							return Math.abs(tooltipItem.xLabel) + ": " + Math.abs(tooltipItem.yLabel).toFixed(6);
						},
					},
				},
				scales: {
					xAxes: [{
						scaleLabel: {
							display: true,
							labelString: 'Shots',
						},
						ticks: {
							stepSize: 1
						},
					}],
					yAxes: [{
						ticks: {
							suggestedMin: 0,
							suggestedMax: 1,
						},
					}],
				}
			}
		});
	}
}

function simulateUpdate(updateHistory = false)
{	
	// Serialize any forms that exist on this page and send them off	
	var params = {
		"defense": serializeForm("#defense_form"),
		"attack": serializeForm("#attack_form"),
	};
	//console.log(params);
	
	$.ajax({
		url: "simulate.json",
		type:"POST",
		data: JSON.stringify(params),
		contentType: "application/json; charset=utf-8",
		dataType: "json",
		success: function(data)
		{			
			if (window.shots_chart != null)
			{				
				window.shots_chart.data.labels = data.shots_to_die_labels;
				window.shots_chart.data.datasets[0].data = data.shots_to_die;
				window.shots_chart.data.datasets[0].borderColor = Array(data.shots_to_die_labels.length).fill('rgb(54, 162, 235)');
				window.shots_chart.data.datasets[0].backgroundColor = Array(data.shots_to_die_labels.length).fill('rgba(54, 162, 235, 0.5)');
				
				// Your ship color
				window.shots_chart.data.datasets[0].borderColor[data.your_ship_index] = 'rgb(255, 99, 132)';
				window.shots_chart.data.datasets[0].backgroundColor[data.your_ship_index] = 'rgba(255, 99, 132, 0.5)';
				
				window.shots_chart.update();
			}
			
			if (window.cdf_chart != null)
			{				
				// NOTE: Skip 0,0 element as it isn't interesting
				var result = data.shots_cdf.slice(1).map(function(item, index) {
					return {
						x: index + 1,
						y: item
					};
				});
				window.cdf_chart.data.datasets[0].data = result;
				window.cdf_chart.options.scales.xAxes[0].ticks.min = 1;
				window.cdf_chart.options.scales.xAxes[0].ticks.max = result.length - 1;
				
				window.cdf_chart.update();
			}		
			
			$("#shots-title").html("Expected Shots: " + data.expected_shots_string);
			
			if (updateHistory && window.history.pushState && data.form_state_string.length > 0)
			{
				window.history.pushState(null, null, "?"+data.form_state_string);
			}
			
			$("html, body").animate({
				scrollTop: $("#simulate-results").offset().top
			}, 300);
		}
	})
}

$(document).ready(function()
{	
	setupCharts();
	
	// If the user goes "back" after we've changed the URL, force a page reload
	// since we don't currently handle all of the content/form updates via AJAX.
	window.addEventListener("popstate", function(e) {
		window.location.reload();
	});	
	// If we have a query string, trigger a simulation automatically (but don't update history)
	if (window.location.search.length > 0) {
		simulateUpdate(false);
	}
	
	// AJAX form submission
	$("#simulate_form").submit(function(event) {
		event.preventDefault();
		// Form submitted by user, so update the history
		simulateUpdate(true);
	});
});
