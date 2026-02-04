#create dataset dir
set dataset_dir "../../../dataset/${design}"
exec mkdir -p $dataset_dir

#cp data
exec cp -r features $dataset_dir
exec cp -r place_label $dataset_dir
exec cp -r route_label $dataset_dir



