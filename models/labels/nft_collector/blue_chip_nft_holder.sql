with blue_chip as (
  select *
  from {{ ref('blue_chip_index') }}
),

contracts as (
  select distinct address
  from {{ source('ethereum', 'contracts') }}
),

erc721_transfer as (
  select
    contract_address as nft_contract_address,
    token_id as nft_token_id,
    wallet_address as to_address,
    block_time
  from {{ ref("transfers_ethereum_erc721") }}
  where amount > 0
),

erc1155_transfer as (
  select
    contract_address as nft_contract_address,
    token_id as nft_token_id,
    wallet_address as to_address,
    block_time
  from {{ ref("transfers_ethereum_erc1155") }}
  where amount > 0
),

cryptopunks_transfer as (
  select *
  from {{ ref('cryptopunks_ethereum_transfers') }}
), 

holder_info as (
  select distinct
    nft_contract_address,
    nft_token_id,
    to_address as holder
  from (
    select
      nft_contract_address,
      nft_token_id,
      to_address,
      row_number()over(partition by nft_contract_address, nft_token_id order by block_time desc) as rank 
    from (
      select * from erc721_transfer
      union distinct
      select * from erc1155_transfer
      union distinct
      select * from cryptopunks_transfer 
    )
    where to_address != '0x0000000000000000000000000000000000000000'
  )
  where rank = 1
)

select distinct
  holder_info.holder as address,
  'NFT Blue Chip Holder' as label,
  'NFT Collector' as label_type
from blue_chip
join holder_info
  on blue_chip.nft_contract_address = holder_info.nft_contract_address
left anti join contracts
  on holder_info.holder = contracts.address
