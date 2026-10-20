# Prints the Muse SessionStart output as plain text: the poteto-mode
# mandate, then the saved model choices when the sheet has any. Run after
# setup-pstack's sheet.awk, with the sheet as input and -v hooks=<this
# directory> found=<1 when the sheet exists>. Only known role lines whose
# entries are model IDs or aliases reach the output, rebuilt from their
# checked values, so no other text in the sheet does. Unlike the Copilot
# sheet check, a panel of one vendor is fine here: Muse serves one family.
{ sheet_add($0) }

END {
  emit("session-start-muse.md")
  if (!found) exit
  n = sheet_roles(roles, panel)
  split("", want)
  for (i = 1; i <= n; i++) want[roles[i]] = 1
  split("", VALUE)
  for (i = 1; i <= SHEET_N; i++) {
    key = sheet_key(SHEET[i])
    if (key in want || key == "default effort") VALUE[key] = sheet_value(SHEET[i])
  }
  lines = ""
  for (i = 1; i <= n; i++) {
    if (!(roles[i] in VALUE)) continue
    if (clean(VALUE[roles[i]])) lines = lines roles[i] ": " VALUE[roles[i]] "\n"
  }
  if (("default effort" in VALUE) && (VALUE["default effort"] == "session" || (VALUE["default effort"] in SHEET_EFFORT))) {
    lines = lines "default effort: " VALUE["default effort"] "\n"
  }
  if (lines == "") exit
  print ""
  emit("session-start-muse-sheet.md")
  printf "%s", lines
}

# A role value is usable when every comma entry is an alias or a model ID,
# once its reasoning effort suffix comes off. Anything else stays out.
function clean(value,    m, E, j, e) {
  m = split(value, E, ",")
  if (m == 0) return 0
  for (j = 1; j <= m; j++) {
    e = sheet_model(sheet_trim(E[j]))
    if (e == "") return 0
    if (!sheet_alias(e) && e !~ /^[a-z0-9][a-z0-9.-]*$/) return 0
  }
  return 1
}

function emit(name,    file, line) {
  file = hooks "/" name
  while ((getline line < file) > 0) print line
  close(file)
}
