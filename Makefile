.SHELLFLAGS = -ec

plan:
	terraform init && terraform plan -refresh=true -out eks.deploy

apply:
	terraform apply eks.deploy

destroy:
	terraform destroy

kubeconfig:
	terraform output kubeconfig > kubeconfig
	export KUBECONFIG=$(PWD)/kubeconfig

config-map-aws-auth:
	terraform output config-map-aws-auth > config-map-aws-auth.yaml
	kubectl apply -f config-map-aws-auth.yaml
	sleep 30
	kubectl wait --for=condition=Ready nodes --all --timeout=360s

private-key:
	terraform output eks_rsa > eks_rsa


.PHONY: \
	plan \
	apply \
	destroy \
	kubeconfig \
	config-map-aws-auth \
	private-key

istio-init-demo:
	istioctl manifest apply --set profile=demo
	kubectl -n istio-system get svc
	kubectl -n istio-system get pods

istio-finalize-demo:
	istioctl manifest generate --set profile=demo | kubectl delete -f -
	kubectl delete ns bookinfo || true
	kubectl delete ns istio-system || true
	kubectl -n istio-system get svc || true
	kubectl -n istio-system get pods || true
