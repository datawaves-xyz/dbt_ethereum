with blue_chip as (
  select *
  from {{ ref('blue_chip') }}
),

contracts as (
  select distinct address
  from {{ source('ethereum', 'contracts') }}
),

erc721_transfer as (
  select
    contract_address as nft_contract_address,
    token_id as nft_token_id,
    to as to_address,
    evt_block_time as block_time
  from {{ source('ethereum_common', 'erc_721_evt_transfer') }}
),

erc1155_single_transfer as (
  select
    contract_address as nft_contract_address,
    id as nft_token_id,
    to as to_address,
    evt_block_time as block_time
  from {{ source('ethereum_common', 'erc_1155_evt_transfer_single') }}
),

erc1155_batch_transfer as (
  select
    contract_address as nft_contract_address,
    explode(ids) as nft_token_id,
    to as to_address,
    evt_block_time as block_time
  from {{ source('ethereum_common', 'erc_1155_evt_transfer_batch') }}
),

cryptopunks_transfer as (
  select
    contract_address as nft_contract_address,
    punk_index as nft_token_id,
    to as to_address,
    evt_block_time as block_time
  from {{ source('ethereum_cryptopunks', 'crypto_punks_market_evt_punk_transfer') }}
  union distinct
  select
    contract_address as nft_contract_address,
    punk_index as nft_token_id,
    to_address,
    evt_block_time as block_time
  from {{ source('ethereum_cryptopunks', 'crypto_punks_market_evt_punk_bought') }}
  union distinct
  select
    contract_address as nft_contract_address,
    punk_index as nft_token_id,
    to as to_address,
    evt_block_time as block_time
  from {{ source('ethereum_cryptopunks', 'crypto_punks_market_evt_assign') }}
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
      select * from erc1155_single_transfer
      union distinct
      select * from erc1155_batch_transfer
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
