import re
from datetime import datetime

sms_sample = """Spent INR 1423
Axis Bank Card no. XX1930
31-08-26 20:30:20 IST
CAS*Only Wh
Avl Limit: INR 116012
Not you? SMS BLOCK 1930 to 919951860002"""

pattern = re.compile(
    r"(?:Spent|spent)\s+(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d+)?)\s*[\r\n]+"
    r"Axis\s+Bank\s+Card\s+no\.\s*(?:XX)?(\d{4})\s*[\r\n]+"
    r"(\d{2}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s*(?:IST)?\s*[\r\n]+"
    r"([^\r\n]+?)\s*[\r\n]+"
    r"(?:Avl\s+Limit|Available\s+Limit)",
    re.IGNORECASE,
)

m = pattern.search(sms_sample)
if m:
    print("MATCH SUCCESS:")
    print("Amount:", m.group(1))
    print("Card:", f"XX{m.group(2)}")
    print("Date:", m.group(3))
    print("Merchant:", m.group(4).strip())
    raw_date = m.group(3)
    parsed_date = datetime.strptime(raw_date, "%d-%m-%y %H:%M:%S")
    print("Parsed datetime:", parsed_date)
else:
    print("NO MATCH")
