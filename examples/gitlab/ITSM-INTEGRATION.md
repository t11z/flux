# Wiring flux to your ITSM (ServiceNow / Jira Service Management)

flux integrates with an ITSM in **two directions**. This guide shows concrete configuration for
both, for **ServiceNow** and **Jira Service Management (JSM)**.

| Direction | What it does | Status |
|-----------|--------------|--------|
| **Outbound** — flux → ITSM | the `commit` job records the change on success | shipped (today) |
| **Inbound** — ITSM → flux | ITSM starts a pipeline (a converge) via the GitLab trigger API | GitLab-native; see the note below |

> **Inbound scope note.** Triggering a pipeline from ITSM works today via GitLab's pipeline
> trigger token (below) — it runs a **full converge** of the current git desired-state
> (`terraform/desired/`). Mapping ITSM **ticket fields → a desired-state record** (so a "publish
> app X" request writes `desired/apps/X.yaml`) is a planned follow-up (the inbound `record` stage).
> Until then, the trigger is ideal for **"approve → deploy the staged change"** and **re-converge /
> heal** flows.

---

## Outbound: flux records the change in your ITSM

On a successful `commit`, the pipeline POSTs this JSON to `$ITSM_WEBHOOK_URL` (skipped if unset):

```json
{ "pipeline": "<CI_PIPELINE_URL>", "commit": "<CI_COMMIT_SHA>", "status": "committed" }
```

You only need an ITSM endpoint that accepts that POST. Set `ITSM_WEBHOOK_URL` as a **masked**
CI/CD variable (Settings ▸ CI/CD ▸ Variables). If your endpoint needs an auth header, also add a
masked `ITSM_AUTH_HEADER` and include it in the `commit` job's curl:

```yaml
# in the commit job, the notification curl:
- |
  if [ -n "$ITSM_WEBHOOK_URL" ]; then
    curl -sf -X POST "$ITSM_WEBHOOK_URL" \
      -H 'Content-Type: application/json' \
      ${ITSM_AUTH_HEADER:+-H "$ITSM_AUTH_HEADER"} \
      -d "{\"pipeline\":\"$CI_PIPELINE_URL\",\"commit\":\"$CI_COMMIT_SHA\",\"status\":\"committed\"}"
  fi
```

### ServiceNow (outbound)

Two common options:

**A. Scripted REST API (secret in the URL — no header needed).** Create a Scripted REST API
(*System Web Services ▸ Scripted REST APIs*) with a resource that validates a query-param token and
opens/updates a change request:

```javascript
// Scripted REST resource: POST /api/x_flux/flux/change
(function process(request, response) {
  if (request.queryParams.token != gs.getProperty('x_flux.webhook_token')) {
    response.setStatus(401); return;
  }
  var body = request.body.data;            // { pipeline, commit, status }
  var cr = new GlideRecord('change_request');
  cr.initialize();
  cr.short_description = 'flux GitOps change ' + body.commit;
  cr.description = 'Pipeline: ' + body.pipeline + '\nStatus: ' + body.status;
  cr.category = 'Network'; cr.state = 3 /* Implement */;
  cr.insert();
})(request, response);
```
Then set `ITSM_WEBHOOK_URL = https://<instance>.service-now.com/api/x_flux/flux/change?token=<secret>`.

**B. Table API + Basic auth.** Point `ITSM_WEBHOOK_URL` at
`https://<instance>.service-now.com/api/now/table/change_request` and set
`ITSM_AUTH_HEADER = Authorization: Basic <base64(user:pass)>` (a dedicated integration user with
the `change_request` write role). The POSTed JSON becomes the record's fields you map.

### Jira Service Management (outbound)

Use a JSM **Automation** rule (*Project settings ▸ Automation*):

1. **Trigger:** *Incoming webhook* → Jira gives you a URL with an embedded secret
   (`https://automation.atlassian.com/pro/hooks/<secret>`). Use it as `ITSM_WEBHOOK_URL` (no auth
   header needed — the secret is in the URL).
2. **Action:** *Create issue* (request type e.g. "Change") — map fields from the webhook payload,
   e.g. Summary = `flux change {{webhookData.commit}}`, Description = `{{webhookData.pipeline}}`.

Direct REST alternative (no automation): POST to
`https://<site>.atlassian.net/rest/servicedeskapi/request` with `ITSM_AUTH_HEADER = Authorization:
Basic <base64(email:api_token)>` and a `requestFieldValues` body.

---

## Inbound: ITSM starts a flux pipeline (GitLab trigger token)

1. In the GitLab project: **Settings ▸ CI/CD ▸ Pipeline trigger tokens ▸ Add** — copy the token,
   store it as a **secret in your ITSM**.
2. ITSM calls, at the right workflow step (e.g. on change approval):

```bash
curl -fsS -X POST \
  --form token="<TRIGGER_TOKEN>" \
  --form ref=main \
  "https://gitlab.com/api/v4/projects/<PROJECT_ID>/trigger/pipeline"
# optional: --form "variables[ANY_CI_VAR]=value"
```

This starts a pipeline that **converges the full git desired-state**. `validate` + `plan` run; on a
real device gate `apply`/`commit` as you prefer (manual, or auto on `CI_PIPELINE_SOURCE=="trigger"`
if you opt into that rule).

### ServiceNow (inbound)

Use a **REST Message** + a **Flow Designer** action (or a Business Rule on change approval):

1. *System Web Services ▸ REST Message* → new message, endpoint
   `https://gitlab.com/api/v4/projects/<PROJECT_ID>/trigger/pipeline`, HTTP method **POST**,
   content-type `application/x-www-form-urlencoded`, body `token=${token}&ref=main`. Store the
   token in a **Credential**/encrypted system property, not inline.
2. In **Flow Designer**, on *Change → Approved*, add a **REST step** that calls the message. Or via
   script:

```javascript
var r = new sn_ws.RESTMessageV2('GitLab flux', 'trigger');
r.setStringParameterNoEscape('token', gs.getProperty('x_flux.trigger_token'));
r.execute();
```

### Jira Service Management (inbound)

A JSM **Automation** rule:

1. **Trigger:** *When a request transitions* → to **Approved** (or a custom "Deploy" transition).
2. **Action:** *Send web request*
   - URL: `https://gitlab.com/api/v4/projects/<PROJECT_ID>/trigger/pipeline`
   - Method: **POST**, type: *Form*
   - Fields: `token = <TRIGGER_TOKEN>` (store via a Jira **secret**/automation variable), `ref = main`
   - (optional) `variables[...] = {{issue.fields...}}` for the future record mapping.

---

## Security checklist

- Store the GitLab **trigger token**, ServiceNow **credentials/properties**, and JSM **webhook
  secret / API token** as **masked secrets** in their respective systems — never inline in code.
- The trigger token only **starts pipelines**; it is not a repo credential. Rotate it if leaked
  (Settings ▸ CI/CD ▸ Pipeline trigger tokens).
- Keep `ITSM_WEBHOOK_URL` (and any `ITSM_AUTH_HEADER`) as **masked** CI/CD variables.
- Prefer secret-in-URL inbound webhooks (JSM Automation, ServiceNow Scripted REST with a token
  check) so flux's outbound POST needs no embedded credentials.
