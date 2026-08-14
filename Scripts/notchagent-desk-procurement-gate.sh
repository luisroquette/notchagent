#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

bom_file="${1:-}"
[[ -f "$bom_file" ]] || {
    echo "Usage: $0 /path/to/private-procurement.json" >&2
    exit 2
}

jq -e '
  .plannedUnits as $plannedUnits |
  .schemaVersion == 4 and
  (keys | sort) == (["schemaVersion","lotAlias","currency","plannedUnits","items"] | sort) and
  (.lotAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
  (.currency == "BRL" or .currency == "USD") and
  (.plannedUnits | type) == "number" and
    .plannedUnits == (.plannedUnits | floor) and .plannedUnits >= 5 and
  ([.items[].id] | sort) == ["data-cable","display","enclosure","packaging"] and
  all(.items[];
    ((keys | sort) == (
      if .id == "display" then
        ["id","supplierAlias","sku","unitCost","minimumOrder","orderQuantity","leadTimeDays","samplePassed",
         "sampleEvidenceFile","sampleEvidenceSHA256"]
      elif .id == "data-cable" then
        ["id","supplierAlias","sku","unitCost","minimumOrder","orderQuantity","leadTimeDays","samplePassed",
         "sampleEvidenceFile","sampleEvidenceSHA256","dataTransferPassed","directMacPassed","dockPassed"]
      elif .id == "enclosure" then
        ["id","supplierAlias","sku","unitCost","minimumOrder","orderQuantity","leadTimeDays","samplePassed",
         "sampleEvidenceFile","sampleEvidenceSHA256","connectorFitPassed","touchAccessPassed","ventilationPassed","bootAccessPassed"]
      elif .id == "packaging" then
        ["id","supplierAlias","sku","unitCost","minimumOrder","orderQuantity","leadTimeDays","samplePassed",
         "sampleEvidenceFile","sampleEvidenceSHA256","onboardingQRIncluded","recoveryCardIncluded"]
      else [] end | sort
    )) and
    (.supplierAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
    (.sku | type) == "string" and (.sku | ascii_upcase) != "PENDING" and
      (.sku | test("\\S")) and
    (.unitCost | type) == "number" and .unitCost > 0 and
    (.minimumOrder | type) == "number" and
      .minimumOrder == (.minimumOrder | floor) and .minimumOrder >= 1 and
    (.orderQuantity | type) == "number" and
      .orderQuantity == (.orderQuantity | floor) and
      .orderQuantity >= $plannedUnits and
      (.orderQuantity % .minimumOrder) == 0 and
    (.leadTimeDays | type) == "number" and
      .leadTimeDays == (.leadTimeDays | floor) and .leadTimeDays >= 1 and
    (.sampleEvidenceFile | type) == "string" and (.sampleEvidenceFile | test("\\S")) and
    (.sampleEvidenceSHA256 | test("^[0-9a-f]{64}$")) and
    .samplePassed == true
  ) and
  ([.items[].sampleEvidenceSHA256] | unique | length) == 4 and
  ([.items[] | .supplierAlias + "\u0000" + .sku] | unique | length) == 4 and
  (.items[] | select(.id == "data-cable") |
    .dataTransferPassed == true and .directMacPassed == true and .dockPassed == true) and
  (.items[] | select(.id == "enclosure") |
    .connectorFitPassed == true and .touchAccessPassed == true and
    .ventilationPassed == true and .bootAccessPassed == true) and
  (.items[] | select(.id == "packaging") |
    .onboardingQRIncluded == true and .recoveryCardIncluded == true)
' "$bom_file" >/dev/null || {
    echo "NOT READY: BOM, cable, enclosure, or packaging evidence is incomplete." >&2
    exit 1
}

all_photo_files=()
all_photo_shas=()
while IFS= read -r item; do
    item_id=$(jq -r '.id' <<<"$item")
    supplier_alias=$(jq -r '.supplierAlias' <<<"$item")
    sku=$(jq -r '.sku' <<<"$item")
    evidence=$(jq -r '.sampleEvidenceFile' <<<"$item")
    expected_sha=$(jq -r '.sampleEvidenceSHA256' <<<"$item")
    [[ -f "$evidence" && ! -L "$evidence" ]] || {
        echo "NOT READY: $item_id sample evidence is missing or is a symlink." >&2
        exit 1
    }
    [[ "$(shasum -a 256 "$evidence" | awk '{print $1}')" == "$expected_sha" ]] || {
        echo "NOT READY: $item_id sample evidence hash does not match." >&2
        exit 1
    }
    jq -e --arg itemId "$item_id" --arg supplierAlias "$supplier_alias" --arg sku "$sku" '
      .schemaVersion == 2 and
      (keys | sort) == (["schemaVersion","itemId","supplierAlias","sku","inspectedAt",
        "inspectorAlias","photoFiles","photoSHA256s","checks","result"] | sort) and
      .itemId == $itemId and .supplierAlias == $supplierAlias and .sku == $sku and
      (.inspectedAt | fromdateiso8601) <= now and
      (.inspectorAlias | test("^[A-Z0-9][A-Z0-9-]{0,31}$")) and
      (.photoFiles | type) == "array" and (.photoFiles | length) >= 2 and
      ([.photoFiles[]] | unique | length) == (.photoFiles | length) and
      all(.photoFiles[]; type == "string" and test("^[^\\r\\n]+$")) and
      (.photoSHA256s | type) == "array" and (.photoSHA256s | length) >= 2 and
      (.photoFiles | length) == (.photoSHA256s | length) and
      ([.photoSHA256s[]] | unique | length) == (.photoSHA256s | length) and
      all(.photoSHA256s[]; test("^[0-9a-f]{64}$")) and
      (.checks | keys | sort) == (
        if $itemId == "display" then ["display","noDeadPixels","touch"]
        elif $itemId == "data-cable" then ["dataTransfer","directMac","dock"]
        elif $itemId == "enclosure" then ["bootAccess","connectorFit","touchAccess","ventilation"]
        elif $itemId == "packaging" then ["onboardingQR","recoveryCard"]
        else [] end) and
      all(.checks[]; . == true) and .result == "pass"
    ' "$evidence" >/dev/null || {
        echo "NOT READY: $item_id sample report is incomplete or does not match procurement." >&2
        exit 1
    }
    photo_files=("${(@f)$(jq -r '.photoFiles[]' "$evidence")}")
    photo_shas=("${(@f)$(jq -r '.photoSHA256s[]' "$evidence")}")
    for (( index = 1; index <= ${#photo_files}; index++ )); do
        photo_file="${photo_files[$index]}"
        [[ -s "$photo_file" && ! -L "$photo_file" ]] || {
            echo "NOT READY: $item_id inspection photo is missing, empty, or linked: $photo_file" >&2
            exit 1
        }
        photo_mime=$(file -b --mime-type "$photo_file")
        [[ "$photo_mime" == image/png || "$photo_mime" == image/jpeg || "$photo_mime" == image/heic ]] || {
            echo "NOT READY: $item_id inspection evidence is not PNG, JPEG, or HEIC: $photo_file" >&2
            exit 1
        }
        [[ "$(shasum -a 256 "$photo_file" | awk '{print $1}')" == "${photo_shas[$index]}" ]] || {
            echo "NOT READY: $item_id inspection photo hash does not match: $photo_file" >&2
            exit 1
        }
        all_photo_files+=("$photo_file")
        all_photo_shas+=("${photo_shas[$index]}")
    done
done < <(jq -c '.items[]' "$bom_file")

unique_photo_file_count=$(printf '%s\n' "${all_photo_files[@]}" | sort -u | wc -l | tr -d '[:space:]')
(( unique_photo_file_count == ${#all_photo_files} )) || {
    echo "NOT READY: inspection photo files are reused across procurement items." >&2
    exit 1
}
unique_photo_sha_count=$(printf '%s\n' "${all_photo_shas[@]}" | sort -u | wc -l | tr -d '[:space:]')
(( unique_photo_sha_count == ${#all_photo_shas} )) || {
    echo "NOT READY: inspection photo contents are reused across procurement items." >&2
    exit 1
}

total_cost=$(jq '[.items[] | .unitCost * .orderQuantity] | add' "$bom_file")
currency=$(jq -r '.currency' "$bom_file")
echo "PASS: procurement BOM and physical sample gates are complete for the pilot lot (${currency} ${total_cost})."
