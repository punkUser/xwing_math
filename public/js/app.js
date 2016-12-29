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

var chart_data =
{
	labels: ["0", "1", "2", "3", "4", "5", "6"],
	datasets: [{
		type: 'line',
		label: 'P(Hits>=x)',
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

window.onload = function()
{
	var ctx = document.getElementById("pdf-canvas").getContext("2d");
	window.pdf_chart = new Chart(ctx, {
		type: 'bar',
		data: chart_data,
		options: {
			responsive: true,
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
};

function simulateUpdateChart(data)
{
	chart_data.labels = data.pdf_x_labels;
	chart_data.datasets[0].data = data.hit_inv_cdf;
	chart_data.datasets[1].data = data.hit_pdf;
	chart_data.datasets[2].data = data.crit_pdf;
	window.pdf_chart.options.title.text = "Expected Total Hits: " + data.expected_total_hits.toFixed(2);
	window.pdf_chart.update();
}

$(document).ready(function()
{
	$('#simulate').click(function(event) {
		event.preventDefault();
		var data = $("#simulate-form").serializeArray();
		$.getJSON('simulate.json', data, simulateUpdateChart);
	});

	// Predator selectors are mutually exclusive
	$('#attack_predator_1').change(function() {
		if (this.checked)
			$('#attack_predator_2').prop("checked", false);
	});
	$('#attack_predator_2').change(function() {
		if (this.checked)
			$('#attack_predator_1').prop("checked", false);
	});

});