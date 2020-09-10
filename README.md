# vaults
Value Vault is the core feature of YFValue in order to achieve long-term profitability of the token.

### Strategy
A strategy must implement the following calls;

 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint256) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()

Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller
