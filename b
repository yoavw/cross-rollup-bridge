#!/bin/sh

network=$1

rm brownie-config.yaml 2>/dev/null

case $network in
	optimism)
		ln -s brownie-config.yaml.ovm brownie-config.yaml
		net=optimism-kovan
		;;
	arbitrum)
		ln -s brownie-config.yaml.evm brownie-config.yaml
		net=arbitrum-kovan
		;;
	kovan)
		ln -s brownie-config.yaml.evm brownie-config.yaml
		net=kovan
		;;
	local)
		ln -s brownie-config.yaml.evm brownie-config.yaml
		net=development
		;;
	*)
		echo "Usage: $0 {optimism|arbitrum|kovan|local}" >&2
		exit 1
		;;
esac

shift

brownie $* --network $net

