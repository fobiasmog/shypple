# Assumptions / Limitations

1. exchange_rates in input data are supposed to be unique for the date: norepeating dates.
2. currency rate key is to eur: usd-eur, jpy-eur, etc.
3. rates are supposed to sorted top-down from oldest to newest: if there is the same sailing_code with different rate - last in array with same sailing_code wins.
4. travels throug sailing legs only possible if next leg is later than previous: no travels to the past.
5. if you have A->B->C, A->X->C, B->X and X->B then trip A->X->B->X->C is not possible. It can be adjusted later if parking fee and limiting time in port will be implemented, not now.
6. 0-day round trips are not possible: A->B->A in same day is not possible.
7. cost calculations should be done in EUR
8. the pause between legs also counts as travel time if in sea 10 days in total and in ports 15 in total than travel time is 25 days
9. if there is more than one route with same price and/or timings (depends of input condition: cheap, fast) then pick up first one
10. if there is no exchange rates or currency for departure date: skip this sailing option and notify user about it
