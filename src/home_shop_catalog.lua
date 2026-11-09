local Food=require("src.home_food_catalog")
local Furniture=require("src.home_furniture_catalog")
local Catalog={PRODUCTS={},ORDER={}}
for id,p in pairs(Food.PRODUCTS) do Catalog.PRODUCTS[id]=p end
for _,id in ipairs(Food.ORDER) do Catalog.ORDER[#Catalog.ORDER+1]=id end
for _,id in ipairs(Furniture.ORDER) do
    local p=Furniture.ITEMS[id]
    local productId=id=="cup" and "mug" or id -- Keep existing grocery-cup receipts and prices valid.
    Catalog.ORDER[#Catalog.ORDER+1]=productId
    Catalog.PRODUCTS[productId]={name=p.name,group="furniture",item=id,servings=1,priceCents=p.priceCents,
        shippingCents=p.shippingCents,minutes=p.minutes,furnitureId=id,dimensions=p.dimensions}
end
return Catalog
