// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;
import "./interfaces/IVoting.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "./Owned.sol";


contract LUXVoting is IVoting, Ownable {

    IERC20 public LUX;

    mapping(address => bool) public coreMember;
    mapping(address => bool) public blocked;
    mapping(string => Proposal) public proposals;
    mapping(string => Voter) public voters;
    mapping(address => mapping(string => VotingAmount)) public votingAmount;
    uint8 public decimals = 18;

    address public withdrawAddress;
    uint256 public proposalFee;

    bool proposingLive;

    constructor(IERC20 coinAddress) Ownable(msg.sender) {
        LUX = coinAddress;
        withdrawAddress = msg.sender;
        proposalFee = 100;
    }

    function changeWithdrawAddress(address _newWithdrawAddress) public onlyOwner override {
        withdrawAddress = _newWithdrawAddress;
    }

    function changeCoinAddress(address _newCoinAddress) public onlyOwner  {
        LUX = IERC20(_newCoinAddress);
    }

    function proposalFeeAmount(uint256 _newAmount) public onlyOwner {
        proposalFee = _newAmount;
    }

    function blockAddress(address target, bool freeze) public onlyOwner override {
        blocked[target] = freeze;
    }

    function whitelist_as_core(address target, bool state) public onlyOwner {
        coreMember[target] = state;
    }
    
    function isBlocked(address _addr) public view  override returns (bool) {
        return blocked[_addr];
    }

     function toggleproposingStatus() public onlyOwner {
        proposingLive = !proposingLive;
    }

    string[] allProposals;
    Voter[] allVoters;


    function getAllProposals () public view returns(Proposal[] memory) {
        Proposal[] memory availableProposals = new Proposal[](allProposals.length);
        
        for (uint256 i = 0; i < allProposals.length; i++) {
                availableProposals[i] = proposals[allProposals[i]];
        }

        return availableProposals;
    }

    function getAllVoters () public view returns(Voter[] memory) {
        Voter[] memory availableVoters = new Voter[](allVoters.length);
        
        for (uint256 i = 0; i < allVoters.length; i++) {
                availableVoters[i] = allVoters[i];
        }

        return availableVoters;
    }


    function addProposals (string memory newProposal, uint40 startTime, uint40 endTime) public {
        require(proposingLive, "Not allowed to make a proposal yet");
        require(!isBlocked(msg.sender), "Sender is blocked");
        require(!proposals[newProposal].exists, "proposal already exists");
        require(endTime > startTime, "proposal timeline invalid");

        if(coreMember[msg.sender] || msg.sender == owner()){
            proposals[newProposal].proposalType = Type(0);
        }
        else{
            proposals[newProposal].proposalType = Type(1);
        }
        proposals[newProposal].proposal = newProposal;
        proposals[newProposal].exists = true;
        proposals[newProposal].voteCount = 0;
        proposals[newProposal].startTime = startTime;
        proposals[newProposal].endTime = endTime;

        if(startTime <= uint40(block.timestamp)){
        proposals[newProposal].proposalStatus = Status(0);
        }
        else{
        proposals[newProposal].proposalStatus = Status(1);
        }

        proposals[newProposal].votes = Votes({approvals: 0, disapprovals: 0});

        allProposals.push(newProposal);
        IERC20(LUX).transferFrom(msg.sender, address(this), (proposalFee * 10 ** uint256(decimals)));
        emit addedProposal(newProposal, startTime);

    }

    function updateProposalStatus (string memory proposal, uint8 _status) public onlyOwner{
        require(proposals[proposal].exists, "proposal does not exist");
        proposals[proposal].proposalStatus = Status(_status);
    }

    function voteProposal(string memory proposal, bool choice) public override {
        require(!isBlocked(msg.sender), "Sender is blocked");
        require(proposals[proposal].exists, "proposal does not exist");
        require(proposals[proposal].proposalStatus != Status.Closed, "proposal has been closed");
        require(proposals[proposal].startTime <= uint40(block.timestamp), "Not allowed to Vote yet");
        require(proposals[proposal].endTime > uint40(block.timestamp), "Voting has ended");

        uint256 amount;

        proposals[proposal].voteCount += 1;
        if(choice == true){
            votingAmount[msg.sender][proposal].approvedTimes += 1;
            proposals[proposal].votes.approvals += 1;
            amount = votingAmount[msg.sender][proposal].approvedTimes * votingAmount[msg.sender][proposal].approvedTimes;
        }
        else{
            votingAmount[msg.sender][proposal].dissaprovedTimes += 1;
            proposals[proposal].votes.disapprovals += 1;
            amount = votingAmount[msg.sender][proposal].dissaprovedTimes * votingAmount[msg.sender][proposal].dissaprovedTimes;
        }
        voters[proposal].proposal = proposal;
        voters[proposal].voterAddress = msg.sender;
        voters[proposal].vote = choice;
        voters[proposal].timestamp = uint40(block.timestamp);

        allVoters.push(voters[proposal]);
        IERC20(LUX).transferFrom(msg.sender, address(this), (amount * 10 ** uint256(decimals)));
        emit votedProposal(proposal, choice);
    }

    function withdraw() public onlyOwner {
      require(IERC20(LUX).balanceOf(address(this)) > 0, "Balance is 0");
      require(withdrawAddress != address(0), "the withdraw address is invalid");
        (bool os, ) = payable(withdrawAddress).call{
            value: address(this).balance
        }("");
        IERC20(LUX).transfer(withdrawAddress, IERC20(LUX).balanceOf(address(this)));
        require(os);
   }

}
