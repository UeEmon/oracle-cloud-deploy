"""Report the Oracle bill to CHUCK so the donation meter goal follows the real running cost.

Needs the dynamic group chuck-cost-reader (this instance) and the policy
"Allow dynamic-group chuck-cost-reader to read usage-reports in tenancy".
The reported amount is the larger of last month's total and this month so far,
so the goal does not drop to zero at the start of each month.
"""
from datetime import datetime, timezone
import json
import os
import urllib.request

import oci


def month_start(day, back=0):
    month=day.year*12+day.month-1-back
    return datetime(month//12,month%12+1,1,tzinfo=timezone.utc)


def total(client,tenancy,start,end):
    details=oci.usage_api.models.RequestSummarizedUsagesDetails(tenant_id=tenancy,time_usage_started=start,time_usage_ended=end,granularity='MONTHLY',query_type='COST')
    items=client.request_summarized_usages(details).data.items
    currencies={i.currency for i in items if i.computed_amount}
    if len(currencies)>1:raise SystemExit(f'several currencies in the bill: {sorted(currencies)}')
    return sum(i.computed_amount or 0 for i in items),(currencies.pop() if currencies else 'USD')


def main():
    signer=oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
    client=oci.usage_api.UsageapiClient(config={'region':signer.region},signer=signer)
    now=datetime.now(timezone.utc)
    last,currency_last=total(client,signer.tenancy_id,month_start(now,1),month_start(now))
    this,currency_this=total(client,signer.tenancy_id,month_start(now),month_start(now,-1))
    amount=max(last,this)
    currency=currency_this if this>=last else currency_last
    if currency=='JPY':usd=amount/float(os.environ.get('CHUCK_JPY_PER_USD') or 150)
    elif currency=='USD':usd=amount
    else:raise SystemExit(f'set a conversion for {currency} in oracle_cost.py')
    url=os.environ.get('CHUCK_COST_URL','http://127.0.0.1:18082')
    request=urllib.request.Request(url+'/api/admin/running-cost',data=json.dumps(dict(source='oracle',usd=round(usd,2))).encode(),
                                   headers={'Content-Type':'application/json','Origin':url,'X-Chuck-Admin':os.environ['CHUCK_ADMIN_SECRET']})
    with urllib.request.urlopen(request,timeout=30) as response:goal=json.load(response)['goal_usd']
    print(f'oracle bill {amount:.2f} {currency} (last month {last:.2f}, this month {this:.2f}) -> ${usd:.2f}; meter goal ${goal:.2f}')


if __name__=='__main__':
    main()
