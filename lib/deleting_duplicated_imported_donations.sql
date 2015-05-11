


-- delete donations from donations inner join
select * from donations inner join
    (select  min(id) minid, donated_at, bank_reference, amount
     from donations
     group by donated_at, bank_reference, amount
     having count(1) > 1) as duplicates
   on (duplicates.donated_at = donations.donated_at
   and duplicates.bank_reference = donations.bank_reference
   and duplicates.amount = donations.amount
   and duplicates.minid <> donations.id);
