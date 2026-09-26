# Email draft — reply to Infosec

**To:** <Infosec发起人>
**CC:** ithelpdesk, Infosec Team
**Subject:** RE: Suspected brute-force attack attempts — llm-postgresql (Investigated & Remediated)

---

Hi <Infosec发起人>,

Thanks for the alert. I've completed the investigation and remediation on `llm-postgresql` (Flexible Server, resource group **<公司RG>**, subscription *<公司Azure订阅>*). Summary below, mapped to your action items:

**1. Verification of the failed login attempts**

- Confirmed the Defender for Cloud alert against the server: 383 failed attempts, **0 successful logins** from `121.173.173.48` — no evidence of compromise.
- Note: the server had no diagnostic settings configured, so PostgreSQL connection logs were not retained; the Defender alert data is the available evidence. Enabling diagnostic logging is now tracked as a follow-up item.

**2. Check for own services / scripting**

- The source IP `121.173.173.48` (Korea) does **not** match any of our egress addresses:
  - Azure Container Apps environments (static outbound IPs `20.187.190.x`, `20.195.90.x`) hosting the 5 applications that use this database
  - Developer workstation (`114.92.x.x`) and ops VPS (`104.194.x.x`)
- Conclusion: none of our services or scripts produced these attempts — this was external brute-force traffic from the internet, exploiting an open firewall.

**3. Root cause & remediation (completed today, zero-downtime)**

- **Root cause:** the server firewall contained an `AllowAll` rule (`0.0.0.0–255.255.255.255`), exposing port 5432 to the entire internet (the "default network settings" you flagged).
- **Actions taken (in this order):**
  1. Added explicit allow rules for the two Azure Container Apps environments' static outbound IPs (business-critical applications)
  2. Added allow rules for the business-required developer/ops IPs listed above
  3. Deleted the `AllowAll` rule
  4. Retained the `AllowAzureServices` (0.0.0.0) rule temporarily as a safety net for other Azure services
- Verified application connectivity after the change — all services are operating normally. The server is no longer reachable from arbitrary public IPs.

**4. Requests to ithelpdesk / Infosec**

- Please share the **corporate VPN / Bastion egress IP addresses** so I can add them to the whitelist.
- Regarding the **Defender for Cloud scan**: I don't appear to have the required permissions from my side — could Infosec run the scan on the affected resources, or grant me the necessary role?

**5. Follow-up hardening (planned)**

- Enable diagnostic settings → Log Analytics for connection auditing
- Evaluate Entra ID (AAD) authentication as you recommended, to eliminate DB-level password brute-forcing
- Longer term: private endpoint + disable public network access

Happy to jump on a call if anything needs further discussion.

Best regards,
Desmond Chen
