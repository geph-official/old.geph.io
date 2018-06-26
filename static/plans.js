function clearPlanSelection() {
    $(".card").removeClass("plan-card-selected")
}

function copyTotalPrice() {
    $("#total-price").text($(".plan-card-selected small").text())
    $("#plan-description").text($(".plan-card-selected strong").text())
}


clearPlanSelection()

$("#onemonth").click(function() {
    clearPlanSelection()
    $("#onemonth").addClass("plan-card-selected")
    $("#months").val("1")
    copyTotalPrice()
})

$("#oneyear").click(function() {
    clearPlanSelection()
    $("#oneyear").addClass("plan-card-selected")
    $("#months").val("12")
    copyTotalPrice()
})

$("#sixmonths").click(function() {
    clearPlanSelection()
    $("#sixmonths").addClass("plan-card-selected")
    $("#months").val("6")
    copyTotalPrice()
})

$("#oneyear").click()
