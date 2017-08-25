$(document).foundation();

window.chartColors =
{
	red: 'rgb(255, 99, 132)',
	orange: 'rgb(255, 159, 64)',
	yellow: 'rgb(255, 205, 86)',
	green: 'rgb(75, 192, 192)',
	blue: 'rgb(54, 162, 235)',
	purple: 'rgb(153, 102, 255)',
	grey: 'rgb(231,233,237)'
};

var pdf_chart_data =
{
	labels: ["0", "1", "2", "3", "4", "5", "6"],
	datasets: [{
		type: 'line',
		label: 'At Least # Hits',
		borderColor: window.chartColors.blue,
		backgroundColor: window.chartColors.blue,
		borderWidth: 2,
		fill: false,
		data: []
	}, {
		type: 'bar',
		label: 'Hits',
		backgroundColor: window.chartColors.red,
		data: []
	}, {
		type: 'bar',
		label: 'Crits',
		backgroundColor: window.chartColors.orange,
		data: [] 
	}]
};

var token_chart_data =
{
	labels: ["Focus", "Target Lock", "Evade", "Stress"],
	datasets: [{
		label: 'Attacker',
		backgroundColor: window.chartColors.red,
		data: []
	}, {
		label: 'Defender',
		backgroundColor: window.chartColors.green,
		data: []
	}]
}

window.onload = function()
{
	var pdf_ctx = document.getElementById("pdf-canvas").getContext("2d");	
	window.pdf_chart = new Chart(pdf_ctx, {
		type: 'bar',
		data: pdf_chart_data,
		options: {
			responsive: true,
			maintainAspectRatio: false,
			title: {
				display: true,
				text: 'Total Hit Probability Distribution',
				fontSize: 24,
			},
			legend: {
				onClick: (e) => e.stopPropagation()
			},
			tooltips: {
				mode: 'index',
				intersect: true,
				callbacks: {
					title: function(tooltipItems, data) {
						var sum = 0;
						tooltipItems.forEach(function(tooltipItem) {
							if (tooltipItem.datasetIndex > 0)
								sum += data.datasets[tooltipItem.datasetIndex].data[tooltipItem.index];
						});
						return sum.toFixed(1) + '%';
					},
					label: function(tooltipItem, data) {
						return data.datasets[tooltipItem.datasetIndex].label + ': ' + tooltipItem.yLabel.toFixed(1) + '%';
					},
				},
			},
			scales: {
				xAxes: [{
					stacked: true,
				}],
				yAxes: [{
					ticks: {
						min: 0,
						max: 100,
					},
					stacked: true
				}]
			}
		}
	});
	
	var token_ctx = document.getElementById("token-canvas").getContext("2d");
	window.token_chart = new Chart(token_ctx, {
		type: 'bar',
		data: token_chart_data,
		options: {
			responsive: true,
			maintainAspectRatio: false,
			title: {
				display: true,
				text: 'Expected Token Delta',
				fontSize: 24,
			},
			legend: {
				position: 'top',
			},
			tooltips: {
				mode: 'index',
				intersect: true,
				callbacks: {
					label: function(tooltipItem, data) {
						return data.datasets[tooltipItem.datasetIndex].label + ': ' + tooltipItem.yLabel.toFixed(3);
					},
				},
			},
			scales: {
				yAxes: [{
					ticks: {
						suggestedMin: -1,
						suggestedMax:  1,
					},
				}]
			}
		}
	});
};

function simulateUpdate(updateHistory = false)
{
	var simulateForm = $("#simulate-form").first();
	var data = simulateForm.serializeArray();
	
	$.post(simulateForm.attr("action"), data, function(data) {
		pdf_chart_data.labels = data.pdf_x_labels;
		pdf_chart_data.datasets[0].data = data.hit_inv_cdf;
		pdf_chart_data.datasets[1].data = data.hit_pdf;
		pdf_chart_data.datasets[2].data = data.crit_pdf;
		window.pdf_chart.options.title.text = "Expected Total Hits: " + data.expected_total_hits.toFixed(2);
		window.pdf_chart.update();
		
		token_chart_data.labels = data.exp_token_labels;
		token_chart_data.datasets[0].data = data.exp_attack_tokens;
		token_chart_data.datasets[1].data = data.exp_defense_tokens;
		window.token_chart.update();

		if (updateHistory && window.history.pushState && data.form_state_string.length > 0)
		{
			window.history.pushState(null, null, "?q="+data.form_state_string);
		}		
	}, 'json');
}

$(document).ready(function()
{
	$('#simulate-form').submit(function(event) {
		event.preventDefault();
		// Form submitted by user, so update the history
		simulateUpdate(true);
	});

	// TODO: Clean this all up
	$('#attack_predator_1').change(function() {
		if (this.checked)
			$('#attack_predator_2').prop("checked", false);
	});
	$('#attack_predator_2').change(function() {
		if (this.checked)
			$('#attack_predator_1').prop("checked", false);
	});
	$('#attack_dengar_1').change(function() {
		if (this.checked)
			$('#attack_dengar_2').prop("checked", false);
	});
	$('#attack_dengar_2').change(function() {
		if (this.checked)
			$('#attack_dengar_1').prop("checked", false);
	});
	$('#attack_guidance_chips_hit').change(function() {
		if (this.checked)
			$('#attack_guidance_chips_crit').prop("checked", false);
	});
	$('#attack_guidance_chips_crit').change(function() {
		if (this.checked)
			$('#attack_guidance_chips_hit').prop("checked", false);
	});
	
	$(".stepper-number").change(function() {
		var max = +($(this).attr('max'));
		var min = +($(this).attr('min'));
		var val = +($(this).val());
		$(this).val(Math.min(Math.max(val, min), max));
    });
	
	$('.stepper-button').click(function() {
		var $input = $(this).parents('.stepper-group').find('.stepper-number');
		var val   = +($input.val());
		var delta = +($(this).data("delta"));
		$input.val(val + delta);
		$input.trigger("change");
	});
	
	// If the user goes "back" after we've changed the URL, force a page reload
	// since we don't currently handle all of the content/form updates via AJAX.
	window.addEventListener("popstate", function(e) {
		window.location.reload();
	});
	
	// If we have a query string, trigger a simulation automatically (but don't update history)
	if (window.location.search.length > 0) {
		simulateUpdate(false);
	}
});