class_name CommunityPublisher
extends GitHubClient

## "Publish to the community": submits a package (.descentpkg) to the community repository as a pull request, from the
## signed-in player's own GitHub account - no browser work, no hand-edited catalog. The player's fork of the repository gets
## a branch with the one package file (packages/<id>/<id>-<version>.descentpkg) and a pull request to the community
## repository is opened. There the package is checked automatically, somebody merges it, and the catalog (index.json) is
## rebuilt by the repository itself - see tools/community in this project for those parts.
##
## `await publish(path)` -> {ok, error, url (the pull request)}; status text arrives via `progress`.

signal progress(text: String)

const UPSTREAM_OWNER := "pieterjanpintens"
const UPSTREAM_REPO := "descent-engine-community"
const UPSTREAM_BRANCH := "main"
## Bigger packages are still fine to share, but not through this button (the file travels inside one API call).
const MAX_PUBLISH_BYTES := 45 * 1048576

## Overridable (tests).
var upstream_owner := UPSTREAM_OWNER
var upstream_repo := UPSTREAM_REPO
## Seconds between checks while GitHub makes the fork.
var fork_poll_seconds := 2.0


## Where a package lives in the community repository.
static func repository_path(id: String, version: String) -> String:
	return "packages/%s/%s-%s.%s" % [id, id, version, SharePackage.EXTENSION]


func publish(package_path: String) -> Dictionary:
	var account := saved_account()
	if account.is_empty():
		return _failed("Sign in with GitHub first.")
	var token := str(account["token"])
	var login := str(account["login"])

	progress.emit("Checking the package...")
	var package := SharePackage.read(package_path)
	if not package["ok"]:
		return _failed("The package is not valid: %s" % "; ".join((package["errors"] as Array).slice(0, 3)))
	var manifest: Dictionary = package["manifest"]
	var id := str(manifest["id"])
	var version := str(manifest["version"])
	var bytes := FileAccess.get_file_as_bytes(package_path)
	if bytes.size() > MAX_PUBLISH_BYTES:
		return _failed("This package is %d MB; the Publish button takes up to %d MB. Share the file itself instead." % [bytes.size() / 1048576, MAX_PUBLISH_BYTES / 1048576])

	var upstream := "%s/repos/%s/%s" % [api_base, upstream_owner, upstream_repo]
	var fork := "%s/repos/%s/%s" % [api_base, login, upstream_repo]
	var file_path := repository_path(id, version)

	progress.emit("Looking at the community list...")
	var existing := await call_json(HTTPClient.METHOD_GET, "%s/contents/%s?ref=%s" % [upstream, file_path.uri_encode().replace("%2F", "/"), UPSTREAM_BRANCH], token)
	if existing["status"] == 200:
		return _failed("Version %s of \"%s\" is already in the community list. Raise the version number and export again." % [version, str(manifest["name"])])
	if existing["status"] == 401:
		sign_out()
		return _failed("GitHub no longer accepts the sign-in - sign in again.")
	if existing["status"] != 404:
		return _failed("The community repository could not be reached (%s)." % _problem(existing))

	var own_repository := login.to_lower() == upstream_owner.to_lower()
	if own_repository:
		# the owner of the community repository can't fork it into their own account - and doesn't need to: the branch goes in the repository itself
		fork = upstream
	else:
		progress.emit("Preparing your copy of the community repository...")
		var forked := await call_json(HTTPClient.METHOD_POST, upstream + "/forks", token, {"default_branch_only": true})
		if forked["status"] != 202 and forked["status"] != 200:
			return _failed("Your copy (fork) of the community repository could not be made (%s)." % _problem(forked))
		var ready := false
		for attempt in 30:  # a new fork takes a few seconds to appear
			var probe := await call_json(HTTPClient.METHOD_GET, "%s/git/ref/heads/%s" % [fork, UPSTREAM_BRANCH], token)
			if probe["status"] == 200:
				ready = true
				break
			await get_tree().create_timer(fork_poll_seconds).timeout
		if not ready:
			return _failed("GitHub is still making your copy of the community repository - try again in a minute.")
		# an older fork is brought up to date, so the pull request only holds this package
		await call_json(HTTPClient.METHOD_POST, fork + "/merge-upstream", token, {"branch": UPSTREAM_BRANCH})
	var head := await call_json(HTTPClient.METHOD_GET, "%s/git/ref/heads/%s" % [fork, UPSTREAM_BRANCH], token)
	var head_sha := str(((head["data"] as Dictionary).get("object", {}) as Dictionary).get("sha", "")) if typeof(head["data"]) == TYPE_DICTIONARY else ""
	if head["status"] != 200 or head_sha == "":
		return _failed("Your copy of the community repository could not be read (%s)." % _problem(head))

	var branch := "submit/%s-%s" % [id, version]
	var made := await call_json(HTTPClient.METHOD_POST, fork + "/git/refs", token, {"ref": "refs/heads/" + branch, "sha": head_sha})
	if made["status"] == 422:  # the branch is there from an earlier try: start it over
		made = await call_json(HTTPClient.METHOD_PATCH, "%s/git/refs/heads/%s" % [fork, branch], token, {"sha": head_sha, "force": true})
	if made["status"] != 201 and made["status"] != 200:
		return _failed("A branch for the package could not be made (%s)." % _problem(made))

	progress.emit("Uploading the package (%.1f MB)..." % (bytes.size() / 1048576.0))
	var title := "%s %s (%s)" % [str(manifest["name"]), version, str(manifest["type"])]
	var uploaded := await _commit_file(fork, token, head_sha, branch, file_path, bytes, "Add " + title)
	if uploaded != "":
		return _failed("The package could not be uploaded (%s)." % uploaded)

	progress.emit("Opening the pull request...")
	var body := "**%s** %s - a %s by %s\n\n%s\n\n_Submitted from the Descent Engine app. sha256 `%s`, %d bytes._" % [
		str(manifest["name"]), version, str(manifest["type"]), str(manifest.get("author", "")) if str(manifest.get("author", "")) != "" else login,
		str(manifest.get("description", "")), FileAccess.get_sha256(package_path), bytes.size()]
	var opened := await call_json(HTTPClient.METHOD_POST, upstream + "/pulls", token, {
		"title": title, "head": "%s:%s" % [login, branch], "base": UPSTREAM_BRANCH, "body": body, "maintainer_can_modify": true})
	if opened["status"] == 201:
		progress.emit("Submitted.")
		return {"ok": true, "error": "", "url": str((opened["data"] as Dictionary).get("html_url", ""))}
	if opened["status"] == 422:  # an open pull request from this branch exists: the upload above already updated it
		var open_ones := await call_json(HTTPClient.METHOD_GET, "%s/pulls?state=open&head=%s:%s" % [upstream, login, branch.uri_encode()], token)
		if open_ones["status"] == 200 and typeof(open_ones["data"]) == TYPE_ARRAY and not (open_ones["data"] as Array).is_empty():
			progress.emit("Submitted (your open request was updated).")
			return {"ok": true, "error": "", "url": str(((open_ones["data"] as Array)[0] as Dictionary).get("html_url", ""))}
	return _failed("The pull request could not be opened (%s)." % _problem(opened))


## Puts one file on `branch` with the git data calls (blob, tree, commit, branch update) instead of the one-call contents API:
## the file is stored first on its own, and a check GitHub does on the push ("repository rule violation ... timed out") only
## sees a small commit. Each call is tried once more after a pause when GitHub answers 409 or a server error. "" = done,
## otherwise what went wrong.
func _commit_file(repo: String, token: String, parent_sha: String, branch: String, file_path: String, bytes: PackedByteArray, message: String) -> String:
	var blob := await _call_again(HTTPClient.METHOD_POST, repo + "/git/blobs", token, {"content": Marshalls.raw_to_base64(bytes), "encoding": "base64"})
	if blob["status"] != 201:
		return "storing the file: " + _problem(blob)
	var parent := await _call_again(HTTPClient.METHOD_GET, "%s/git/commits/%s" % [repo, parent_sha], token)
	if parent["status"] != 200 or typeof(parent["data"]) != TYPE_DICTIONARY:
		return "reading the repository: " + _problem(parent)
	var base_tree := str(((parent["data"] as Dictionary).get("tree", {}) as Dictionary).get("sha", ""))
	var tree := await _call_again(HTTPClient.METHOD_POST, repo + "/git/trees", token, {
		"base_tree": base_tree,
		"tree": [{"path": file_path, "mode": "100644", "type": "blob", "sha": str((blob["data"] as Dictionary).get("sha", ""))}]})
	if tree["status"] != 201:
		return "building the commit: " + _problem(tree)
	var commit := await _call_again(HTTPClient.METHOD_POST, repo + "/git/commits", token, {
		"message": message, "tree": str((tree["data"] as Dictionary).get("sha", "")), "parents": [parent_sha]})
	if commit["status"] != 201:
		return "making the commit: " + _problem(commit)
	var moved := await _call_again(HTTPClient.METHOD_PATCH, "%s/git/refs/heads/%s" % [repo, branch], token, {
		"sha": str((commit["data"] as Dictionary).get("sha", "")), "force": true})
	if moved["status"] != 200:
		return "updating the branch: " + _problem(moved)
	return ""


## call_json(), once more after a pause when GitHub answers 409 (conflict / rule check timed out) or a server error.
func _call_again(method: HTTPClient.Method, url: String, token: String, body: Variant = null) -> Dictionary:
	var answer := await call_json(method, url, token, body)
	if int(answer["status"]) == 409 or int(answer["status"]) >= 500:
		await get_tree().create_timer(4.0).timeout
		answer = await call_json(method, url, token, body)
	return answer


func _failed(text: String) -> Dictionary:
	progress.emit(text)
	return {"ok": false, "error": text, "url": ""}
