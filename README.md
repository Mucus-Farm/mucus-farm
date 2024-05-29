# Implementation Notes
Here are some notes from way back about how this contract system works
This is a project I did for a client that fell through, so I took this opportunity to open it up to being public.
This project was supposed to be a variation of Wolf Game, but with some pokemon like evolution mechanics mixed in
From the project, the most notable file I’d say is MucusFarm.sol
I remember putting in a bit of time to figure out the mechanics for it

### $Mucus
- 6% transaction fees
	- 4% for LP stakers
	- 1% for team
	- 1% for liquidity

### Frogs and Dogs NFT
- 2 types of NFTs: frogs and dogs
- Every even tokenId will be a dog
- Every odd tokenId will be a frog
- tokenSupply = 6000
- First 20% will be minted in ETH
- Last 80% will be minted with MUCUS
	- minting can only happen through [[breeding]]
	- breeding has a 10% chance of the NFT being minted to be stolen
		- RNG via Chainlink VRF
- Royalaties on buy and sells of NFTs
	- Opensea
- tokenIds past 6000 are reserved for giga frogs and chad dogs
	- same schema: 
		- even => chad dog
		- odd => giga frog
	- Can only be minted by sacrificing 3 NFTs from the same faction (ie: 3 frogs or 3 dogs)
	- staking gigaChad gives 3x the normal yield
	- gigaChads have a chance to steal the opposing faction NFTs when they are being minted **ONLY** when that faction is souped up
- A faction is souped up if that faction has more liquidity staked for that faction than the other faction
	- ie: 
		- total dog faction stake: 100 LP
		- total frog faction stake: 110 LP
		- souped up: frog faction

### Mucus Farming
- Staking normal frogs or dogs will yield 1000 $MUCUS per day
- Staking gigas or chads will yield 3000 $MUCUS per day (3x the normal amount)
- staking gigas or chads allow them to have the chance to steal from the opposing faction when they are being bred **ONLY** when that faction is souped up
- all yield will be taxed, based on which faction is souped up
	- the losing faction will be taxed 20% on all their yield and will be claimable by the winning faction
	- the winning faction will be taxed 5% on all their yield and it will be burned

### Liquidity Staking
- L2 pool where those who stake liquidity will earn a portion of 4% on all trades through the uniswap pool (plus 0.5% from regular staking through uniswap)
	- how the trading fee is distributed is based on an inverse ratio of the amount of LP staked for the dogs vs the frogs.
	- (opposing faction LP amount / total LP amount) * 4%
	- Example:
		- 50 LP staked for dogs
		- 100 LP staked for frogs
		- (50 / 150) * 4 = 1.33% for frogs
		- (100 / 150) * 4 = 2.66% for dogs
	- This encourages the amount staked between the 2 factions to be somewhat equal

### Soup Mode
- souped up determines which faction is winning
- Every 12 hours, a new soup cycle will occur
	- it will check to see how much LP is staked for each faction
	- if FROG > DOG then the frogs will enter soup mode
	- if DOG > FROG then the dogs will enter soup mode
