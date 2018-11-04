function bind_node_tree_handlers()
{
	$(".modify-node-child-button").click(function() {
		var child_index = $(this).data("child-index");
		var child_depth = $(this).data("child-depth");
		
		var child_element = $(this);
		$(".modify-node").each(function(index) {
			if ($(this).data("node-depth") >= child_depth)
				$(this).addClass("hide");
			if ($(this).data("node-index") == child_index)
			{
				$(this).removeClass("hide");
				child_element = $(this);
			}
		});
		
		$("html, body").animate({
			scrollTop: child_element.offset().top
		}, 300);
	});
}

function simulateUpdate(updateHistory = false)
{	
	// Serialize any forms that exist on this page and send them off	
	var params = {
		"attack":  serializeForm("#attack_form"),
		"defense": serializeForm("#defense_form"),
		"roll":    serializeForm("#roll_form"),
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
			$("#modify-tree").html(data.modify_tree_html);
			bind_node_tree_handlers();

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
