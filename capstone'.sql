# Analyze year-over-year revenue growth and identify peak performing years.
select
extract(year from str_to_date(orderdate, '%m/%d/%Y')) as year,
sum(p.productprice * s.orderquantity) as total_revenue
from (
    select * from sales_2015
    union all
    select * from sales_2016
) s
join products p
on s.productkey = p.productkey
group by
extract(year from str_to_date(orderdate, '%m/%d/%Y'))
order by
year;



# Rank product categories by total sales and compare margins across categories.
with all_sales as (
    select * from sales_2015
    union all
    select * from sales_2016 )
select
    c.categoryname,
    sum(s.orderquantity * p.productprice) as total_sales,
    sum(s.orderquantity * (p.productprice - p.productcost)) as total_margin,
    round(
        (sum(s.orderquantity * (p.productprice - p.productcost)) / nullif(sum(s.orderquantity * p.productprice), 0)) * 100,
        2
    ) as margin_percentage
from all_sales s
join products p on s.productkey = p.productkey
join subcategories sc on p.productsubcategorykey = sc.productsubcategorykey
join categories c on sc.productcategorykey = c.productcategorykey
group by c.categoryname  order by total_sales desc;

    

# Identify the best- and worst-selling products in terms of quantity sold and revenue generation.
WITH combined_sales AS (SELECT
    p.productname, SUM(s.orderquantity) AS total_quantity_sold,
    SUM(s.orderquantity * p.productprice) AS total_revenue
  FROM (
      SELECT * FROM sales_2015
      UNION ALL
      SELECT * FROM sales_2016
    ) s
  JOIN products p ON s.productkey = p.productkey
  GROUP BY p.productname )
SELECT productname, total_quantity_sold, total_revenue,
  RANK() OVER (ORDER BY total_quantity_sold DESC) AS qty_best_rank,
  RANK() OVER (ORDER BY total_quantity_sold ASC) AS qty_worst_rank,
  RANK() OVER (ORDER BY total_revenue DESC) AS revenue_best_rank,
  RANK() OVER (ORDER BY total_revenue ASC) AS revenue_worst_rank FROM combined_sales
ORDER BY qty_best_rank LIMIT 20;


# Segment customers based on their total lifetime spend (e.g., low, mid, high) and determine their share of total revenue.
WITH customer_spend AS ( SELECT s.customerkey, SUM(s.orderquantity * p.productprice) AS total_spend
FROM ( SELECT * FROM sales_2015
      UNION ALL
      SELECT * FROM sales_2016
    ) s
  JOIN products p ON s.productkey = p.productkey
  GROUP BY s.customerkey
),
spend_segments AS ( SELECT customerkey, total_spend,
    CASE
      WHEN total_spend < 1000 THEN 'Low'
      WHEN total_spend BETWEEN 1000 AND 5000 THEN 'Mid'
      ELSE 'High'
    END AS spend_segment
  FROM customer_spend),
segment_revenue AS ( SELECT spend_segment, SUM(total_spend) AS segment_revenue
  FROM spend_segments GROUP BY spend_segment),
total_revenue AS (
  SELECT SUM(total_spend) AS total_rev FROM customer_spend
)
SELECT sr.spend_segment, sr.segment_revenue,
  ROUND((sr.segment_revenue / tr.total_rev) * 100, 2) AS revenue_share_percentage
FROM segment_revenue sr, total_revenue tr ORDER BY segment_revenue DESC;


# Identify top countries and regions by total sales and average order size.
SELECT t.country, t.region,
  SUM(s.orderquantity * p.productprice) AS total_sales,
  ROUND(AVG(s.orderquantity * p.productprice), 2) AS avg_order_size
FROM (
    SELECT * FROM sales_2015
    UNION ALL
    SELECT * FROM sales_2016
  ) s
JOIN products p ON s.productkey = p.productkey
JOIN territories t ON s.territorykey = t.salesterritorykey
GROUP BY t.country, t.region ORDER BY total_sales DESC LIMIT 10;


# Rank sales territories by profit margin percentage and highlight high-margin regions.
select t.region, t.country,
  sum(s.orderquantity * (p.productprice - p.productcost)) as profit,
  sum(s.orderquantity * p.productprice) as revenue,
  round(sum(s.orderquantity * (p.productprice - p.productcost)) / 
  nullif(sum(s.orderquantity * p.productprice), 0) * 100, 2) as profit_margin_percentage
from
  (select * from sales_2015 union all select * from sales_2016) s
join products p on s.productkey = p.productkey
join territories t on s.territorykey = t.salesterritorykey
group by t.region, t.country order by profit_margin_percentage desc;
  
# Calculate the return rate per category or product, and spotlight items with the highest returns
with sales_union as ( select * from sales_2015
  union all
  select * from sales_2016 ),
sales_agg as (
  select p.productkey, sc.productcategorykey, cat.categoryname,
         sum(s.orderquantity) as total_sales_qty
  from sales_union s
  join products p on s.productkey = p.productkey
  join subcategories sc on p.productsubcategorykey = sc.productsubcategorykey
  join categories cat on sc.productcategorykey = cat.productcategorykey
  group by p.productkey, sc.productcategorykey, cat.categoryname),
  
returns_agg as (
  select p.productkey, sc.productcategorykey, cat.categoryname,
         sum(r.returnquantity) as total_return_qty
  from returns r
  join products p on r.productkey = p.productkey
  join subcategories sc on p.productsubcategorykey = sc.productsubcategorykey
  join categories cat on sc.productcategorykey = cat.productcategorykey
  group by p.productkey, sc.productcategorykey, cat.categoryname
)
select s.categoryname, s.productkey, r.total_return_qty, s.total_sales_qty,
round(r.total_return_qty / nullif(s.total_sales_qty, 0) * 100, 2) as return_rate_percentage
from sales_agg s
join returns_agg r on s.productkey = r.productkey
order by return_rate_percentage desc
limit 10;


# Detect monthly or quarterly sales peaks and troughs—identify key seasonal patterns.
# Monthly Sales Trend
select
  date_format(str_to_date(orderdate, '%m/%d/%Y'), '%Y-%m') as `year_month`,
  sum(orderquantity * productprice) as total_sales
from
  (select * from sales_2015 union all select * from sales_2016) s
join products p on s.productkey = p.productkey
group by `year_month` order by `year_month`;
  
# Quarterly Sales Trend
select
  concat(year(str_to_date(orderdate, '%m/%d/%Y')), '-q', quarter(str_to_date(orderdate, '%m/%d/%Y'))) as `year_quarter`,
  sum(orderquantity * productprice) as total_sales
from
  (select * from sales_2015 union all select * from sales_2016) s
join products p on s.productkey = p.productkey
group by `year_quarter` order by `year_quarter`;



  
# Determine revenue contribution from new customers versus repeat purchasers and assess changes over time.
with customer_first_order as ( select customerkey,
min(str_to_date(orderdate, '%m/%d/%Y')) as first_order_date
from (select * from sales_2015 union all select * from sales_2016) s
group by customerkey
),
sales_with_flag as (
select s.orderdate, s.customerkey, p.productprice, s.orderquantity, cfo.first_order_date,
    case
      when str_to_date(s.orderdate, '%m/%d/%Y') = cfo.first_order_date then 'new_customer'
      else 'repeat_customer'
    end as customer_type,
    (p.productprice * s.orderquantity) as revenue,
    date_format(str_to_date(s.orderdate, '%m/%d/%Y'), '%Y-%m') as `year_month`
  from
    (select * from sales_2015 union all select * from sales_2016) s
  join customer_first_order cfo on s.customerkey = cfo.customerkey
  join products p on s.productkey = p.productkey
)
select `year_month`, customer_type, sum(revenue) total_revenue
from sales_with_flag
group by `year_month`, customer_type
order by `year_month`, customer_type;
