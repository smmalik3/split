#!/bin/bash
set -e
B=http://localhost:8787
echo "== create group =="
CREATE=$(curl -s -X POST $B/api/groups -H 'Content-Type: application/json' -d '{"name":"Goa Trip","nickname":"Salman"}')
echo "$CREATE" | python3 -m json.tool | head -12
CODE=$(echo "$CREATE" | python3 -c "import sys,json; print(json.load(sys.stdin)['code'])")
MID=$(echo "$CREATE" | python3 -c "import sys,json; print(json.load(sys.stdin)['your_member_id'])")
echo "CODE=$CODE MID=$MID"
echo "== join as Zeeshan =="
JOIN=$(curl -s -X POST $B/api/groups/$CODE/join -H 'Content-Type: application/json' -d '{"nickname":"Zeeshan"}')
MID2=$(echo "$JOIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['your_member_id'])")
echo "MID2=$MID2"
echo "== OCR receipt =="
OCR=$(curl -s -X POST $B/api/groups/$CODE/ocr -F "receipt=@data/test/receipt.png")
echo "$OCR" | python3 -m json.tool
TOTAL=$(echo "$OCR" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total'))")
MERCHANT=$(echo "$OCR" | python3 -c "import sys,json; print(json.load(sys.stdin).get('merchant'))")
RECEIPT=$(echo "$OCR" | python3 -c "import sys,json; print(json.load(sys.stdin).get('receipt'))")
echo "parsed total=$TOTAL merchant=$MERCHANT receipt=$RECEIPT"
echo "== add expense (OCR result) =="
curl -s -X POST $B/api/groups/$CODE/expenses -H 'Content-Type: application/json' -d "{\"member_id\":$MID,\"merchant\":\"$MERCHANT\",\"total\":$TOTAL,\"note\":\"Dinner\",\"receipt\":\"$RECEIPT\"}" | python3 -c "import sys,json; d=json.load(sys.stdin); print('total now:', d['total'], '| expenses:', len(d['expenses']))"
echo "== add manual expense by Zeeshan =="
curl -s -X POST $B/api/groups/$CODE/expenses -H 'Content-Type: application/json' -d "{\"member_id\":$MID2,\"merchant\":\"Taxi\",\"total\":20.00,\"note\":\"Airport\"}" | python3 -c "import sys,json; d=json.load(sys.stdin); print('total now:', d['total'], '| expenses:', len(d['expenses']))"
echo "== balances =="
curl -s $B/api/groups/$CODE/balances | python3 -m json.tool
echo "== receipt image serves? =="
curl -s -o /dev/null -w "%{http_code}\n" $B/uploads/$RECEIPT
