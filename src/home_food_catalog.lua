local Catalog={}
Catalog.ITEMS={
    basic_meal={name="Ready meal",sprite=8,eatingSprite=9,action="eat"},
    sandwich={name="Sandwich",sprite=10,action="sandwich"},
    cereal={name="Bowl of cereal",sprite=12,action="cereal"},
    pizza_slice={name="Pizza slice",sprite=5,action="pizza"},
    chinese_meal={name="Chinese takeout serving",sprite=7,action="takeout"},
    bottled_drink={name="Bottled drink",sprite=16,action="bottle"},
    cup={name="Ceramic cup",sprite=15},
    bread={name="Bread portion",sprite=11,ingredient=true},
    vegetables={name="Vegetable portion",sprite=13,ingredient=true},
    cooked_meal={name="Home-cooked vegetables and toast",sprite=9,action="hotmeal"},
    good_meal={name="Well-seasoned vegetables and toast",sprite=9,action="goodmeal"},
    plain_meal={name="Overdone vegetables and toast",sprite=9,action="plainmeal"},
    good_sandwich={name="Carefully prepared sandwich",sprite=10,action="goodsandwich"},
    rough_sandwich={name="Roughly prepared sandwich",sprite=10,action="roughsandwich"},
}
Catalog.PRODUCTS={
    meal={name="Ready meal",group="groceries",item="basic_meal",servings=1,priceCents=500,shippingCents=100,minutes=60,sprite=8},
    meal_pack={name="Four ready meals",group="groceries",item="basic_meal",servings=4,priceCents=1800,shippingCents=100,minutes=60,sprite=2},
    sandwich={name="Fresh sandwich",group="groceries",item="sandwich",servings=1,priceCents=300,shippingCents=100,minutes=60,sprite=10},
    cereal={name="Cereal box",group="groceries",item="cereal",servings=1,priceCents=200,shippingCents=100,minutes=60,sprite=12},
    drink={name="Bottled drink",group="groceries",item="bottled_drink",servings=1,priceCents=200,shippingCents=100,minutes=60,sprite=16},
    cup={name="Basic ceramic cup",group="groceries",item="cup",servings=1,priceCents=250,shippingCents=100,minutes=60,sprite=15},
    pizza={name="Pizza — four servings",group="takeout",item="pizza_slice",servings=4,priceCents=1600,shippingCents=200,minutes=30,sprite=4},
    chinese={name="Chinese food — two servings",group="takeout",item="chinese_meal",servings=2,priceCents=1200,shippingCents=200,minutes=30,sprite=7},
    bread={name="Bread — four portions",group="groceries",item="bread",servings=4,priceCents=400,shippingCents=100,minutes=60,sprite=11},
    vegetables={name="Vegetables — four portions",group="groceries",item="vegetables",servings=4,priceCents=600,shippingCents=100,minutes=60,sprite=13},
}
Catalog.ORDER={"meal","meal_pack","sandwich","cereal","drink","cup","pizza","chinese","bread","vegetables"}
function Catalog.isFood(id) local item=Catalog.ITEMS[id];return item and (item.action~=nil or item.ingredient==true) or false end
return Catalog
