{{
  cte_import([
    ('transactions', 'stg_transactions'),
    ('traces', 'stg_traces'),
    ('cryptopunksmarket_evt_assign', 'cryptopunks_CryptoPunksMarket_evt_Assign')
  ])
}},

prices_usd as (
  select *
  from {{ var('prices_usd') }}
  where contract_address = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
    and dt >= '{{ var("start_ts") }}'
    and dt < '{{ var("end_ts") }}'
),

erc721_token_transfers as (
  select *
  from {{ ref('ERC721_evt_Transfer') }}
  where `from` = '0x0000000000000000000000000000000000000000'
    and dt >= '{{ var("start_ts") }}'
    and dt < '{{ var("end_ts") }}'
),

erc1155_token_transfers as (
  select *
  from {{ ref('ERC1155_evt_TransferSingle') }}
  where `from` = '0x0000000000000000000000000000000000000000'
    and dt >= '{{ var("start_ts") }}'
    and dt < '{{ var("end_ts") }}'
),

erc721_mint_tx as (
  select
    a.hash as tx_hash,
    b.contract_address as nft_contract_address,
    b.tokenId as nft_token_id,
    b.evt_block_time,
    b.dt,
    b.to as minter,
    sum(a.value) - sum(case when c.value is null then 0 else c.value end) as value
  from transactions as a
  join erc721_token_transfers as b
   on a.hash = b.evt_tx_hash
  left join (
    select
      transaction_hash,
      from_address,
      to_address,
      value
    from traces
    where status = 1
  ) as c
   on a.hash = c.transaction_hash and a.from_address = c.to_address and a.to_address = c.from_address
  group by a.hash, b.contract_address, b.tokenId, b.evt_block_time, b.dt, b.to
),

erc721_mint as (
  select
    x.tx_hash,
    x.nft_contract_address,
    x.nft_token_id,
    x.evt_block_time,
    x.dt,
    x.minter,
    y.avg_value / y.num_of_items / power(10, 18) as eth_mint_price
  from erc721_mint_tx as x
  left join (
    select
      tx_hash,
      avg(value) as avg_value,
      count(distinct nft_token_id) as num_of_items
    from erc721_mint_tx
    group by tx_hash
  ) as y
   on x.tx_hash = y.tx_hash
),

erc1155_mint_tx as (
  select
    a.hash as tx_hash,
    b.contract_address as nft_contract_address,
    b.id as nft_token_id,
    b.evt_block_time,
    b.dt,
    b.to as minter,
    a.value,
    b.value as quanity
  from transactions as a
  join erc1155_token_transfers as b
   on a.hash = b.evt_tx_hash
),

erc1155_mint as (
  select
    x.tx_hash,
    x.nft_contract_address,
    x.nft_token_id,
    x.evt_block_time,
    x.dt,
    x.minter,
    y.avg_value / y.num_of_items / power(10, 18) as eth_mint_price
  from erc1155_mint_tx as x
  left join (
    select
      tx_hash,
      avg(value) as avg_value,
      sum(quanity) as num_of_items
    from erc1155_mint_tx
    group by tx_hash
  ) as y
   on x.tx_hash = y.tx_hash
),

mint_union as (
    select
      *,
      'erc721' as erc_standard
    from erc721_mint

    union all
    select
      *,
      'erc_1155' as erc_standard
    from erc1155_mint

    union all
    select
      evt_tx_hash as tx_hash,
      '0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb' as nft_contract_address,
      punkIndex as nft_token_id,
      evt_block_time,
      dt,
      to as minter,
      0 as eth_mint_price,
      'erc20' as erc_standard
    from cryptopunksmarket_evt_assign
)

select
  u.tx_hash,
  u.nft_contract_address,
  u.nft_token_id,
  u.evt_block_time,
  u.dt,
  u.minter,
  u.erc_standard,
  eth_mint_price,
  eth_mint_price * p.price as usd_mint_price
from mint_union as u
left join prices_usd as p
  on p.minute = {{ dbt_utils.date_trunc('minute', 'u.evt_block_time') }}
