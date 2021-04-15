// For local testing using Ganache, the test fails due to block increments issue with Ganache
// please re-run the test file 3 more times to get accurate results

const { assert } = require('chai');
const truffleAssert = require('truffle-assertions');

const SMD = artifacts.require('./SMD_v5.sol');
const Token = artifacts.require('./Token.sol');
const TestToken = artifacts.require('./TestToken.sol');

require('chai')
    .use(require('chai-as-promised'))
    .should();

contract('SMD', (accounts) => {
    let instance, token, rewardToken;
    const totalSupply = 200000000000000000000;
    before(async() => {
        token = await Token.new("LPToken", "LP", 18, totalSupply.toString(), accounts[0]);
        rewardToken = await TestToken.new("RewardToken", "REW", 18, totalSupply.toString(), accounts[0]);
        instance = await SMD.new(token.address, rewardToken.address);
    })

    describe('Deployment', async() => {
        it('deploys successfully', async() => {
            const address = instance.address;
            assert.notEqual(address, 0x0);
            assert.notEqual(address, '');
            assert.notEqual(address, null);
            assert.notEqual(address, undefined);
        })

        it('has a token address', async() => {
            const tokenAddress = await instance.tokenAddress();
            tokenAddress.should.equal(token.address);
        })

        it('has a reward token address', async() => {
            const rewardTokenAddress = await instance.rewardTokenAddress();
            rewardTokenAddress.should.equal(rewardToken.address);
        })

        it('should be paused after deployment', async() => {
            const paused = await instance.isPaused();
            paused.should.equal(true, "Contract is paused");
        })

        it('should set period to 0 during deployment', async() => {
            const period = await instance.period();
            period.toString().should.equal('0', "Period is set successfully");
        })
    })

    describe('Reset, reward and StartEnd Blocks', async() => {
        it('should not add 0 rewards', async() => {
            await truffleAssert.reverts(instance.resetAndsetStartEndBlock(0, 1000, 1100), "Reward must be positive");
        })

        it('should not add reward greater than allowance', async() => {
            const approval = 1000000000000000000;
            const rewards = 2000000000000000000;
            await rewardToken.approve(instance.address, approval.toString());
            await truffleAssert.reverts(instance.resetAndsetStartEndBlock(rewards.toString(), 1000, 1100), "Make sure to add enough allowance");
        })

        it('should not add invalid parameters for start and end block', async() => {
            const currentBlock = await instance.currentBlock();
            // console.log(currentBlock);
            const start = currentBlock + 5;
            const end = currentBlock + 15;
            await truffleAssert.reverts(instance.resetAndsetStartEndBlock(1, currentBlock - 1, currentBlock + 10), "Start should be more than current block");
            await truffleAssert.reverts(instance.resetAndsetStartEndBlock(1, start, start - 5), "End block should be greater than start");
        })

        it('should not allow others to set start and end block', async() => {
            await truffleAssert.reverts(instance.resetAndsetStartEndBlock(1, 10, 20, {from: accounts[1]}), "Ownable: caller is not the owner");
        })

        it('should add reward amount and set the start, end block by the owner', async() => {
            const reward = 1000000000000000000;
            const currentBlock = await instance.currentBlock();
            await instance.resetAndsetStartEndBlock(reward.toString(), currentBlock.toNumber() + 25, currentBlock.toNumber() + 125);
            const startBlock = await instance.startingBlock();
            startBlock.toString().should.equal((currentBlock.toNumber() + 25).toString(), "Starting block set successfully");
            const totalReward = await instance.totalReward();
            totalReward.toString().should.equal(reward.toString(), "Reward set successfully");
        })

        it('should not be paused after setting start and end block', async() => {
            const pause = await instance.isPaused();
            pause.should.equal(false, "Is not paused");
        })

        it('should not allow users to stake before start', async() => {
            const stake = 10000000000000000000;
            await token.transfer(accounts[1], stake.toString());
            await token.approve(instance.address, stake.toString(), {from: accounts[1]});
            await truffleAssert.reverts(instance.stake(stake.toString(), {from: accounts[1]}), "Invalid period");
        })
    })

    describe('Users can stake, claim and withdraw rewards', async() => {

        it('should allow users to stake', async() => {
            const stake = 10000000000000000000;
            const currentBlock = await instance.currentBlock();
            const start = await instance.startingBlock();
            for(let i = currentBlock; i<= start; i++) {
                await instance.incBlock();
            }
            // console.log(await instance.currentBlock());
            await instance.stake(stake.toString(), {from: accounts[1]});
            const userStakeDetails = await instance.userDeposits(accounts[1]);
            userStakeDetails[0].toString().should.equal(stake.toString(), "Amount staked successfully");
        })

        it('should update user share in the pool', async() => {
            const userShare = await instance.fetchUserShare(accounts[1]);
            userShare.toString().should.equal('10000', "share set successfully");
        })

        it('should update claim rewards per block', async() => {
            const currentUserRew = await instance.calculate(accounts[1]);
            await instance.incBlock();
            const newUserRew = await instance.calculate(accounts[1]);
            // const diff = newUserRew.toNumber() - currentUerRew.toNumber();
            const diff = newUserRew.sub(web3.utils.toBN(currentUserRew));
            const rewPerBlock = await instance.rewPerBlock();
            rewPerBlock.toString().should.equal(diff.toString(), "Rewards are calculated");
        })

        it('should change userShare as the pool increases', async() => {
            const stake = 10000000000000000000;
            await token.transfer(accounts[2], stake.toString());
            await token.approve(instance.address, stake.toString(), {from: accounts[2]});
            await instance.stake(stake.toString(), {from: accounts[2]});
            const userStakeShare1 = await instance.fetchUserShare(accounts[1]);
            const userStakeShare2 = await instance.fetchUserShare(accounts[2]);
            userStakeShare1.toString().should.equal('5000', "User share updated");
            userStakeShare2.toString().should.equal('5000', "User share updated");
        })

        it('should allow users to claim correct rewards', async() => {
            await instance.incBlock();
            const rew = await instance.calculate(accounts[1]);
            const rewardBalance = await rewardToken.balanceOf(accounts[1]);
            await instance.claimRewards({from: accounts[1]});
            await instance.incBlock();
            const rew1 = await instance.calculate(accounts[1]);
            const newRewardBalance = await rewardToken.balanceOf(accounts[1]);
            const newRew = rew.add(web3.utils.toBN(rew1));
            const diff = newRewardBalance.sub(web3.utils.toBN(rewardBalance));
            newRew.toString().should.equal(diff.toString(), "Rewards are claimed correctly");
        })

        it('should allow users to withdraw stakings', async() => {
            await instance.emergencyWithdraw({from: accounts[2]});
            const userDeposit = await instance.userDeposits(accounts[2]);
            userDeposit[0].toString().should.equal('0', "Withdraw is successfull");
            const hasStaked = await instance.hasStaked(accounts[2]);
            hasStaked.should.equal(false, "Has staked removed");
        })

        it('should allow users to add more liquidity', async() => {
            const stake = 10000000000000000000;
            await token.transfer(accounts[2], stake.toString());
            await token.approve(instance.address, stake.toString(), {from: accounts[2]});
            await instance.stake(stake.toString(), {from: accounts[2]});
            const newStake = 30000000000000000000;
            await token.transfer(accounts[1], newStake.toString());
            await token.approve(instance.address, newStake.toString(), {from: accounts[1]});
            await instance.stake(newStake.toString(), {from: accounts[1]});
            const userShare1 = await instance.fetchUserShare(accounts[1]);
            userShare1.toString().should.equal('8000', "User share increased after adding of liquidity");
        })

        it('should not allow users to stake after the endingBlock', async() => {
            const currentBlock = await instance.currentBlock();
            const end = await instance.endingBlock();
            for(let i = currentBlock; i<= end; i++) {
                await instance.incBlock();
            }
            const newStake = 30000000000000000000;
            await token.transfer(accounts[1], newStake.toString());
            await token.approve(instance.address, newStake.toString(), {from: accounts[1]});
            await truffleAssert.reverts(instance.stake(newStake.toString(), {from: accounts[1]}), "Invalid period");
        })

        it('should allow users to claim rewards in buffer period', async() => {
            await instance.incBlock();
            const rew = await instance.calculate(accounts[1]);
            const rewardBalance = await rewardToken.balanceOf(accounts[1]);
            await instance.claimRewards({from: accounts[1]});
            await instance.incBlock();
            const rew1 = await instance.calculate(accounts[1]);
            const newRewardBalance = await rewardToken.balanceOf(accounts[1]);
            const newRew = rew.add(web3.utils.toBN(rew1));
            const diff = newRewardBalance.sub(web3.utils.toBN(rewardBalance));
            newRew.toString().should.equal(diff.toString(), "Rewards are claimed correctly");
        })
    })

    describe("Post-lock period", async() => {
        it('should not allow users to reset the contract', async() => {
            await truffleAssert.reverts(instance.resetAndsetStartEndBlock(1, 1000, 1100, {from: accounts[1]}), "Ownable: caller is not the owner")
        })

        it('should not add reward greater than allowance', async() => {
            const approval = 1000000000000000000;
            const rewards = 2000000000000000000;
            await rewardToken.approve(instance.address, approval.toString());
            await truffleAssert.reverts(instance.resetAndsetStartEndBlock(rewards.toString(), 1000, 1100), "Make sure to add enough allowance");
        })

        it('should not add invalid parameters for start and end block', async() => {
            const currentBlock = await instance.currentBlock();
            // console.log(currentBlock);
            const start = currentBlock + 5;
            const end = currentBlock + 15;
            await truffleAssert.reverts(instance.resetAndsetStartEndBlock(1, currentBlock - 1, currentBlock + 10), "Start should be more than current block");
            await truffleAssert.reverts(instance.resetAndsetStartEndBlock(1, start, start - 5), "End block should be greater than start");
        })

        it('should not allow others to set start and end block', async() => {
            await truffleAssert.reverts(instance.resetAndsetStartEndBlock(1, 10, 20, {from: accounts[1]}), "Ownable: caller is not the owner");
        })

        it('should add reward amount and set the start, end block by the owner', async() => {
            const reward = 1000000000000000000;
            const currentBlock = await instance.currentBlock();
            await instance.resetAndsetStartEndBlock(reward.toString(), currentBlock.toNumber() + 15, currentBlock.toNumber() + 115);
            const startBlock = await instance.startingBlock();
            startBlock.toString().should.equal((currentBlock.toNumber() + 15).toString(), "Starting block set successfully");
            const totalReward = await instance.totalReward();
            totalReward.toString().should.equal(reward.toString(), "Reward set successfully");
        })

        it('should not be paused after setting start and end block', async() => {
            const pause = await instance.isPaused();
            pause.should.equal(false, "Is not paused");
        })

        it('should increment the period', async() => {
            const period = await instance.period();
            period.toString().should.equal('2', "Period is set correctly");
        })
    })

    describe("Users can renew and claim old rewards", async() => {
        it('should not allow users to claim untill renew', async() => {
            const currentBlock = await instance.currentBlock();
            const start = await instance.startingBlock();
            for(let i = currentBlock; i<= start; i++) {
                await instance.incBlock();
            }
            await instance.incBlock();
            await truffleAssert.reverts(instance.claimRewards({from: accounts[1]}), "No stakes found for user");
        })

        it('should allow users to renew', async() => {
            await instance.renew({from: accounts[1]});
            const userDeposits = await instance.userDeposits(accounts[1]);
            const period = await instance.period();
            userDeposits[3].toString().should.equal(period.toString(), "Renewed successfully");
        })

        it('should allow users to claim correct rewards', async() => {
            await instance.incBlock();
            const rew = await instance.calculate(accounts[1]);
            const rewardBalance = await rewardToken.balanceOf(accounts[1]);
            await instance.claimRewards({from: accounts[1]});
            await instance.incBlock();
            const rew1 = await instance.calculate(accounts[1]);
            const newRewardBalance = await rewardToken.balanceOf(accounts[1]);
            const newRew = rew.add(web3.utils.toBN(rew1));
            const diff = newRewardBalance.sub(web3.utils.toBN(rewardBalance));
            newRew.toString().should.equal(diff.toString(), "Rewards are claimed correctly");
        })

        it('should allow users to claim rewards for old period', async() => {

            const oldRewards = await instance.viewOldRewards(accounts[2]);
            const rewBalance = await rewardToken.balanceOf(accounts[2]);
            await instance.claimOldRewards({from: accounts[2]});
            const newBalance = await rewardToken.balanceOf(accounts[2]);
            const diff = newBalance.sub(web3.utils.toBN(rewBalance));
            diff.toString().should.equal(oldRewards.toString(), "Old rewards claimed successfully");
        })

        it('should allow users to withdraw at any time', async() => {
            await instance.emergencyWithdraw({from: accounts[2]});
            const userDeposits = await instance.userDeposits(accounts[2]);
            userDeposits[0].toString().should.equal('0', "Withdraw successfull");
        })

        it('should allow users to exit', async() => {
            await instance.incBlock();
            const tokenBalance = await token.balanceOf(accounts[1]);
            const amount = await instance.userDeposits(accounts[1]);
            await instance.incBlock();
            await instance.withdraw({from: accounts[1]});
            await instance.incBlock();
            const newtokenBalance = await token.balanceOf(accounts[1]);
            const diffT = newtokenBalance.sub(web3.utils.toBN(tokenBalance));
            amount[0].toString().should.equal(diffT.toString(), "LP tokens are claimed correctly");
        })

    })
})