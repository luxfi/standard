# DELETE JAVASCRIPT FILE
rm javascript_build/test/LamportTest.spec.js 
rm javascript_build/test/LamportTest2.spec.js 

# COMPILE TYPECRIPT FILE
npx tsc 

# RUN JAVASCRIPT FILE
# truffle test javascript_build/test/LamportTest.spec.js --bail --show-events --network rinkeby 
# truffle test javascript_build/test/LamportTest.spec.js --bail --show-events --network goerli 
# truffle test javascript_build/test/LamportTest.spec.js --bail --show-events --network moonbase 
# truffle test javascript_build/test/LamportTest.spec.js --bail --show-events 
truffle test javascript_build/test/LamportTest2.spec.js --bail --show-events 