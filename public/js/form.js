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

var simulate_results = []

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
	var pdf_element = document.getElementById("pdf-canvas");
	if (pdf_element != null)
	{
		var pdf_ctx = pdf_element.getContext("2d");	
		window.pdf_chart = new Chart(pdf_ctx, {
			type: 'bar',
			data: pdf_chart_data,
			options: {
				responsive: true,
				maintainAspectRatio: false,
				title: {
					display: false,
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
							return sum.toFixed(2) + '%';
						},
						label: function(tooltipItem, data) {
							return data.datasets[tooltipItem.datasetIndex].label + ': ' + tooltipItem.yLabel.toFixed(2) + '%';
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
	}

	var token_element = document.getElementById("token-canvas");
	if (token_element != null)
	{
		var token_ctx = token_element.getContext("2d");
		window.token_chart = new Chart(token_ctx, {
			type: 'bar',
			data: token_chart_data,
			options: {
				responsive: true,
				maintainAspectRatio: false,
				title: {
					display: false,
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
	}
};

function updateCharts()
{	
	// Grab the attack index from the slider if it is present, otherwise use the last element
	var attack_number = simulate_results.length;
	if (simulate_results.length == 0) return;
		
	var input = $("#attack_results_number");
	if (input.length > 0)
	{
		attack_number = Math.min(input.val(), simulate_results.length);
	}
	
	//console.log("updateCharts " + attack_number);
	
	// NOTE: UI/attack_number is 1-based
	var result = simulate_results[attack_number - 1];
	
	pdf_chart_data.labels = result.pdf_x_labels;
	pdf_chart_data.datasets[0].data = result.hit_inv_cdf;
	pdf_chart_data.datasets[1].data = result.hit_pdf;
	pdf_chart_data.datasets[2].data = result.crit_pdf;
	
	if (window.pdf_chart != null)
	{
		window.pdf_chart.update();
	}
	
	if (window.token_chart != null)
	{
		token_chart_data.labels = result.exp_token_labels;
		token_chart_data.datasets[0].data = result.exp_attack_tokens;
		token_chart_data.datasets[1].data = result.exp_defense_tokens;
		window.token_chart.update();
	}
	
	$("#pdf-title").html(
		"Expected Total Hits: " + result.expected_total_hits.toFixed(3) +
		"<br>At Least One Crit: " + result.at_least_one_crit.toFixed(2) + "%");
	
	$("#pdf-table").html(result.pdf_table_html);
	$("#token-table").html(result.token_table_html);
}

var current_attack_result_index = -1;
function attackResultsSliderChanged()
{
	var input = $("#attack_results_number");
	var value = input.val();
	if (value == current_attack_result_index) return;
	current_attack_result_index = value;
	
	updateCharts();
}

function simulateUpdate(updateHistory = false)
{
	var simulateForm = $("#simulate-form").first();
	var params = simulateForm.serializeArray();
	
	$.post(simulateForm.attr("action"), params, function(data)
	{
		//console.log(simulate_data);
				
		simulate_results = data.results;
		
		// Resize attack index slider (if present)
		var slider = $('#attack_results_slider');
		if (slider.length > 0)
		{
			if (simulate_results.length == 1)
				slider.addClass("disabled");
			else
				slider.removeClass("disabled");
		
			// NOTE: Seems like replacing the slider with a new instance is the only way
			// to get it to reset properly when endpoints are changed.		
			new Foundation.Slider(slider, {
				start:		    1,
				end:          	simulate_results.length,
				initialStart: 	simulate_results.length,
			});
		}
		
		updateCharts();

		if (updateHistory && window.history.pushState && data.form_state_string.length > 0)
		{
			window.history.pushState(null, null, "?q="+data.form_state_string);
		}
		
		$("html, body").animate(
		{
			scrollTop: $("#pdf-table").offset().top
		}, 300);
	}, 'json');
}

$(document).ready(function()
{
	// AJAX form submission
	$("#simulate-form").submit(function(event) {
		event.preventDefault();
		// Form submitted by user, so update the history
		simulateUpdate(true);
	});
	
	// Mutually exclusive checkboxes
	$(".switch-mutex").find("input").change(function () {
		var root = $(this).parents(".switch-mutex");
		var state = this.checked;
		root.find("input").prop("checked", false);
		$(this).prop("checked", state);
	});
	
	// Stepper range clamping
	$(".stepper-number").change(function() {
		var max = +($(this).attr("max"));
		var min = +($(this).attr("min"));
		var val = +($(this).val());
		$(this).val(Math.min(Math.max(val, min), max));
    });
	// Stepper +/- buttons
	$(".stepper-button").click(function() {
		var input = $(this).parents(".stepper-group").find(".stepper-number");
		var val   = +(input.val());
		var delta = +($(this).data("delta"));
		input.val(val + delta);
		input.trigger("change");
	});
	// Stepper set value buttons
	$(".stepper-button-set").click(function() {
		var input = $(this).parents(".stepper-group").find(".stepper-number");
		var val   = +(input.val());
		var set   = +($(this).data("set"));
		input.val(set);
		input.trigger("change");
	});
	
	// Attack results number
	$("#attack_results_number").change(attackResultsSliderChanged);
	$("#attack_results_slider").on("moved.zf.slider", attackResultsSliderChanged);
	
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
