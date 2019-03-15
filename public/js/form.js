function serializeForm(formName)
{
	var formObject = $(formName).first();
	var formArray = formObject.serializeArray();
	
	var returnArray = {};
	for (var i = 0; i < formArray.length; i++){
		returnArray[formArray[i]['name']] = formArray[i]['value'];
	}
	return returnArray;
}

$(document).ready(function()
{
	// Mutually exclusive checkboxes
	$(".switch-mutex").find("input").change(function () {
		var root = $(this).parents(".switch-mutex");
		var state = this.checked;
		root.find("input").prop("checked", false);
		$(this).prop("checked", state);
	});
	
	// Toggle hidden on all ".token-field" classes in the current form
	$(".switch-hide-token-field").find("input").change(function () {
		var root = $(this).parents("form");
		var state = this.checked;
		var target_elements = root.find(".token-field");
		if (state) {
			target_elements.hide();
		} else {
			target_elements.show();
		}
		$(this).prop("checked", state);
	});
	// Ensure initial visibility is consistent with form state
	$(".switch-hide-token-field").find("input").trigger("change");
	
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
	
	// Clamped stepper values
	$(".stepper-group-clamp").find("input").change(function () {
		var root = $(this).parents(".stepper-group-clamp");
		var changedThis = $(this);
		var changedVal = +(changedThis.val());
				
		// >=
		root.find(".stepper-group-clamp-ge").find("input").each(function () {
			if (!$(this).is(changedThis)) {
				if (+($(this).val()) < changedVal) {
					$(this).val(changedVal);
					$(this).trigger("change");
				}
			}
		});
		// <=
		root.find(".stepper-group-clamp-le").find("input").each(function () {
			if (!$(this).is(changedThis)) {
				if (+($(this).val()) > changedVal) {
					$(this).val(changedVal);
					$(this).trigger("change");
				}
			}
		});
	});
});