class_name CampaignLink
extends Resource

## One way forward from a chapter: "when the chapter's mission ends like this, go to that
## chapter". A chapter with no link for the outcome it ended with is simply played again
## (a lost mission is retried by default). Campaign variable conditions come later.

enum Outcome { WIN, LOSE, ANY }

@export var target_id: String = ""
@export var outcome: Outcome = Outcome.WIN


static func outcome_name(value: int) -> String:
	match value:
		Outcome.WIN:
			return "on win"
		Outcome.LOSE:
			return "on lose"
	return "always"
