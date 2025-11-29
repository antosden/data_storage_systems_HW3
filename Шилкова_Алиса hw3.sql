-- 1. Вывести распределение (количество) клиентов по сферам деятельности, отсортировав результат по убыванию количества.
select 
	job_industry_category, 
	count(1) as client_count 
from customer c
group by 1
order by 2 desc;


-- 2. Найти общую сумму дохода (list_price*quantity) по всем подтвержденным заказам за каждый месяц по сферам деятельности клиентов. Отсортировать результат по году, месяцу и сфере деятельности.
select 
	extract(year from order_date::date) as year, 
	extract(month from order_date::date) as month, 
	job_industry_category, 
	sum(list_price*quantity) 
from orders o 
	join order_items oi on oi.order_id = o.order_id
	join product p on oi.product_id = p.product_id
	join customer c on c.customer_id = o.customer_id
where o.order_status = 'Approved'
group by 1, 2, 3
order by 1, 2, 3;

-- 3. Вывести количество уникальных онлайн-заказов для всех брендов в рамках подтвержденных заказов клиентов из сферы IT. 
-- Включить бренды, у которых нет онлайн-заказов от IT-клиентов, — для них должно быть указано количество 0.

with brands_with_it_cust as (
	select 
		p.brand, 
		job_industry_category,
		case 
			when job_industry_category = 'IT' then count(distinct o.order_id)
			else 0
		end count
	from orders o 
		join order_items oi on oi.order_id = o.order_id
		join product p on oi.product_id = p.product_id
		left join customer c on c.customer_id = o.customer_id 
	where o.order_status = 'Approved'
	group by 1, 2
)
select 
	brand, sum(count)
from brands_with_it_cust bwic
group by 1;



-- 4. Найти по всем клиентам: сумму всех заказов (общего дохода), максимум, минимум и количество заказов, а также среднюю сумму заказа по каждому клиенту. 
--Отсортировать результат по убыванию суммы всех заказов и количества заказов. 
-- Выполнить двумя способами: 

--1) используя только GROUP BY 
select 
	c.customer_id, 
	sum(list_price*quantity) as sum_sales,
	min(list_price*quantity) as min_sales,
	max(list_price*quantity) as max_sales,
	count(o.order_id) as count_orders,
	avg(list_price*quantity) as avg_sales
from customer c
	join orders o on o.customer_id =c.customer_id 
	join order_items oi on oi.order_id = o.order_id 
	join product p on oi.product_id = p.product_id
group by 1
order by 2 desc, 5 desc

-- 2) и используя только оконные функции. Сравнить результат.
select 
	distinct c.customer_id,
	sum(list_price*quantity) over(cust_id) as sum_sales,
	min(list_price*quantity) over(cust_id) as min_sales,
	max(list_price*quantity) over(cust_id) as max_sales,
	count(o.order_id) over(cust_id) as count_orders,
	avg(list_price*quantity) over(cust_id) as avg_sales
from customer c
	join orders o on o.customer_id =c.customer_id 
	join order_items oi on oi.order_id = o.order_id 
	join product p on oi.product_id = p.product_id
window cust_id as (partition by c.customer_id)
order by 2 desc, 5 desc

-- 5. Найти имена и фамилии клиентов с топ-3 минимальной и топ-3 максимальной суммой транзакций за весь период 
--(учесть клиентов, у которых нет заказов, приняв их сумму транзакций за 0).

with top_customers as (
	select 
		distinct c.first_name || ' ' ||  c.last_name as name, 
		case
			when list_price is not null and quantity is not null then sum(list_price*quantity) over(partition by c.customer_id)
			else 0
		end sum_sales 
	from customer c
		left join orders o on o.customer_id =c.customer_id 
		left join order_items oi on oi.order_id = o.order_id 
		left join product p on oi.product_id = p.product_id
		order by 2
)
select 'TOP 3 MIN:' as name, null as sum_sales
union all
(select * from top_customers limit 3)
union all
select 'TOP 3 MAX:', null
union all
(select * from top_customers order by 2 desc limit 3) ;


-- 6. Вывести только вторые транзакции клиентов (если они есть) с помощью оконных функций. 
-- Если у клиента меньше двух транзакций, он не должен попасть в результат.
with transactions as (
    select
        o.*,
        row_number() over (partition by customer_id order by order_id) as order_rn,
        count(1) over (partition by customer_id) as transact_count
    from orders o
)
select 
	customer_id, 
	order_id, 
	order_rn, 
	order_date, 
	online_order, 
	order_status
from transactions t
where transact_count >= 2
  and order_rn in (1, 2);

-- 7. Вывести имена, фамилии и профессии клиентов, а также длительность максимального интервала (в днях) между двумя последовательными заказами. 
--Исключить клиентов, у которых только один или меньше заказов.
with transactions as (
    select
        o.customer_id,
        o.order_date,
        lead(o.order_date) over (
            partition by o.customer_id
            order by o.order_date
        ) as next_order_date
    from orders o
),
gaps as (
    select
        customer_id,
        (next_order_date::date - order_date::date) as gap_days
    from transactions
    where next_order_date is not null
),
gaps_with_max as (
    select
        customer_id,
        gap_days,
        max(gap_days) over (partition by customer_id) as max_gap_days
    from gaps
)
select distinct
    c.first_name,
    c.last_name,
    c.job_title,
    g.max_gap_days
from gaps_with_max g
join customer c on c.customer_id = g.customer_id

-- 8. Найти топ-5 клиентов (по общему доходу) в каждом сегменте благосостояния (wealth_segment). 
-- Вывести имя, фамилию, сегмент и общий доход. Если в сегменте менее 5 клиентов, вывести всех.
with transactions as (
    select
        c.customer_id,
        c.first_name || ' ' ||  c.last_name as name,
        c.wealth_segment,
        sum(coalesce(list_price, 0) * coalesce(quantity, 0)) as total_sum
    from customer c
    join orders o on o.customer_id = c.customer_id
    join order_items oi on oi.order_id = o.order_id
    join product p on oi.product_id = p.product_id
    group by 1, 2, 3
), ranked as (
    select
        customer_id,
        name,
        wealth_segment,
        total_sum,
        row_number() over (
            partition by wealth_segment
            order by total_sum desc
        ) as rn
    from transactions
)
select
    wealth_segment,
    rn,
    name,
    total_sum
from ranked
where rn <= 5     
order by 1, 4 desc;
