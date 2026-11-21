extends RefCounted
class_name IDMLedgerService

## Double-entry journal foundation. Values are positive integer sen; each
## transaction must balance before it is committed and its ID is idempotent.
var entries: Array[Dictionary] = []
var transaction_ids: Dictionary = {}

func post_transaction(transaction_id: String, company_id: String, source_id: String, lines: Array[Dictionary]) -> bool:
	if transaction_id.is_empty() or company_id.is_empty() or source_id.is_empty():
		return false
	if transaction_ids.has(transaction_id) or lines.size() < 2:
		return false
	var debits := 0
	var credits := 0
	for line in lines:
		var account := str(line.get("account", ""))
		var side := str(line.get("side", ""))
		var amount: Variant = line.get("amount_sen", -1)
		if account.is_empty() or side not in ["debit", "credit"]:
			return false
		if typeof(amount) != TYPE_INT or int(amount) <= 0:
			return false
		if side == "debit":
			debits += int(amount)
		else:
			credits += int(amount)
	if debits != credits:
		return false
	for line in lines:
		entries.append({
			"transaction_id": transaction_id,
			"company_id": company_id,
			"source_id": source_id,
			"account": str(line["account"]),
			"side": str(line["side"]),
			"amount_sen": int(line["amount_sen"]),
			"category": str(line.get("category", "")),
		})
	transaction_ids[transaction_id] = true
	return true

func account_balance_sen(account: String) -> int:
	var balance := 0
	for entry in entries:
		if entry["account"] != account:
			continue
		var amount: int = entry["amount_sen"]
		balance += amount if entry["side"] == "debit" else -amount
	return balance

func transaction_is_posted(transaction_id: String) -> bool:
	return transaction_ids.has(transaction_id)

func journal_is_balanced() -> bool:
	var totals: Dictionary = {}
	for entry in entries:
		var id: String = entry["transaction_id"]
		if not totals.has(id):
			totals[id] = {"debit": 0, "credit": 0}
		totals[id][entry["side"]] += int(entry["amount_sen"])
	for total in totals.values():
		if total["debit"] != total["credit"]:
			return false
	return true
